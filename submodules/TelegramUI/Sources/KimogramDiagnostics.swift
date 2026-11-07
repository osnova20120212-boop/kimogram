import Foundation
import UIKit
import Darwin
import MachO

/// Kimogram: a tiny crash and launch reporter for builds installed outside the App Store.
///
/// A sideloaded app often closes without leaving a report the user can find. This records
/// the launch stage the app reached and, on a crash, the reason and the call stack, in the
/// app's own Documents folder. On the next launch the app shows that report instead of
/// starting, with a button that copies it, so the user can send it to the developer.
enum KimogramDiagnostics {
    /// Set by `prepareLaunch()` when a report from the previous launch is waiting to be shown.
    static private(set) var pendingReport: String?
    private static var reportWindow: UIWindow?

    private static var directoryPath: String {
        let documents = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? NSTemporaryDirectory()
        return documents + "/kimogram-diagnostics"
    }
    private static var stagePath: String { return directoryPath + "/stage.txt" }
    private static var crashPath: String { return directoryPath + "/crash.txt" }

    /// The crash file path as a C string, prepared before any signal can arrive.
    private static var crashPathC: UnsafeMutablePointer<CChar>?

    /// Call first thing at launch. Returns true when the previous launch failed and its report
    /// should be shown instead of starting the app.
    static func prepareLaunch() -> Bool {
        let fileManager = FileManager.default
        let _ = try? fileManager.createDirectory(atPath: directoryPath, withIntermediateDirectories: true, attributes: nil)

        var report: String?
        if let crash = try? String(contentsOfFile: crashPath, encoding: .utf8), !crash.isEmpty {
            report = crash
        } else if let stage = try? String(contentsOfFile: stagePath, encoding: .utf8), !stage.isEmpty {
            report = "Приложение закрылось без ошибки на этапе запуска:\n\(stage)"
        }
        let _ = try? fileManager.removeItem(atPath: crashPath)
        let _ = try? fileManager.removeItem(atPath: stagePath)

        if var report {
            report += "\n\n" + deviceSummary()
            report += "\n\n--- последние строки журнала ---\n" + latestLogTail()
            pendingReport = report
            return true
        }

        crashPathC = strdup(crashPath)
        installHandlers()
        return false
    }

    /// Records how far the launch got. Cleared once the app has run for a while.
    static func mark(_ stage: String) {
        let line = "\(stage) (\(Date()))\n"
        if let handle = FileHandle(forWritingAtPath: stagePath) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8) ?? Data())
            handle.closeFile()
        } else {
            let _ = try? line.write(toFile: stagePath, atomically: false, encoding: .utf8)
        }
    }

    /// The launch went through: forget the stages.
    static func launchSucceeded() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) {
            let _ = try? FileManager.default.removeItem(atPath: stagePath)
        }
    }

    // MARK: - Showing the report

    static func showReport(in scene: UIWindowScene) {
        guard let report = pendingReport else {
            return
        }
        let window = UIWindow(windowScene: scene)
        let controller = KimogramDiagnosticsViewController(report: report)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        reportWindow = window
    }

    // MARK: - Recording a crash

    private static func installHandlers() {
        NSSetUncaughtExceptionHandler { exception in
            let text = "Исключение: \(exception.name.rawValue)\n\(exception.reason ?? "")\n\n" + exception.callStackSymbols.joined(separator: "\n")
            KimogramDiagnostics.writeCrash(text)
        }
        for signalNumber in [SIGABRT, SIGSEGV, SIGBUS, SIGTRAP, SIGILL, SIGFPE] {
            signal(signalNumber) { received in
                KimogramDiagnostics.writeCrash("Сигнал \(received)\n\n" + Thread.callStackSymbols.joined(separator: "\n"))
                signal(received, SIG_DFL)
                raise(received)
            }
        }
    }

    private static func writeCrash(_ text: String) {
        guard let path = crashPathC else {
            return
        }
        let fd = open(path, O_CREAT | O_WRONLY | O_TRUNC, 0o644)
        if fd < 0 {
            return
        }
        let stage = (try? String(contentsOfFile: stagePath, encoding: .utf8)) ?? ""
        let full = "Вылет\n\nЭтапы запуска:\n\(stage)\n\(text)\n"
        full.withCString { pointer in
            let _ = write(fd, pointer, strlen(pointer))
        }
        close(fd)
    }

    // MARK: - Context

    private static func deviceSummary() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let bundleId = Bundle.main.bundleIdentifier ?? "?"
        var loadAddress = ""
        if let header = _dyld_get_image_header(0) {
            loadAddress = String(format: "0x%lx, slide 0x%lx", UInt(bitPattern: header), _dyld_get_image_vmaddr_slide(0))
        }
        return "Kimogram \(version) (\(build)), \(bundleId)\niOS \(UIDevice.current.systemVersion), \(UIDevice.current.model)\nадрес: \(loadAddress)"
    }

    private static func latestLogTail() -> String {
        guard let appGroupLike = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return "(нет)"
        }
        let candidates = [
            appGroupLike.appendingPathComponent("kimogram-shared/telegram-data/logs/app-logs").path
        ]
        for directory in candidates {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
                continue
            }
            var newest: (path: String, date: Date)?
            for name in names {
                let path = directory + "/" + name
                if let date = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date {
                    if newest == nil || date > newest!.date {
                        newest = (path, date)
                    }
                }
            }
            if let newest, let data = FileManager.default.contents(atPath: newest.path) {
                let tail = data.suffix(6000)
                return String(decoding: tail, as: UTF8.self)
            }
        }
        return "(нет)"
    }
}

private final class KimogramDiagnosticsViewController: UIViewController {
    private let report: String

    init(report: String) {
        self.report = report
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .systemBackground

        let title = UILabel()
        title.text = "Kimogram закрылся с ошибкой"
        title.font = .boldSystemFont(ofSize: 20)
        title.numberOfLines = 0

        let subtitle = UILabel()
        subtitle.text = "Нажмите «Скопировать отчёт» и отправьте его разработчику. Потом закройте приложение и откройте снова."
        subtitle.font = .systemFont(ofSize: 15)
        subtitle.textColor = .secondaryLabel
        subtitle.numberOfLines = 0

        let textView = UITextView()
        textView.text = self.report
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.backgroundColor = .secondarySystemBackground
        textView.layer.cornerRadius = 10

        let button = UIButton(type: .system)
        button.setTitle("Скопировать отчёт", for: .normal)
        button.titleLabel?.font = .boldSystemFont(ofSize: 17)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 12
        button.addTarget(self, action: #selector(self.copyPressed(_:)), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [title, subtitle, textView, button])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(stack)

        let guide = self.view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: guide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -16),
            button.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    @objc private func copyPressed(_ sender: UIButton) {
        UIPasteboard.general.string = self.report
        sender.setTitle("Скопировано ✓", for: .normal)
    }
}
