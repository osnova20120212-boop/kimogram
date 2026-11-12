package org.telegram.ui.kimogram;

import android.app.Activity;

import org.telegram.messenger.LocaleController;
import org.telegram.messenger.R;
import org.telegram.messenger.UserObject;
import org.telegram.messenger.kimogram.KimogramConfig;
import org.telegram.tgnet.TLRPC;
import org.telegram.ui.ActionBar.AlertDialog;

/** Kimogram: "Спрашивать перед звонком". */
public final class KimogramCallConfirm {

    private static boolean confirmed;

    private KimogramCallConfirm() {
    }

    /**
     * Returns true when the call must wait for the user's answer; {@code call} then runs again
     * after "Позвонить".
     */
    public static boolean askFirst(Activity activity, TLRPC.User user, boolean video, Runnable call) {
        if (confirmed) {
            confirmed = false;
            return false;
        }
        if (activity == null || user == null || !KimogramConfig.get(KimogramConfig.CONFIRM_CALLS)) {
            return false;
        }
        String name = UserObject.getUserName(user);
        new AlertDialog.Builder(activity)
            .setTitle(video ? KimogramConfig.t("Видеозвонок", "Video call") : KimogramConfig.t("Звонок", "Call"))
            .setMessage(KimogramConfig.t("Позвонить: ", "Call ") + name + "?")
            .setPositiveButton(KimogramConfig.t("Позвонить", "Call"), (d, w) -> {
                confirmed = true;
                call.run();
            })
            .setNegativeButton(LocaleController.getString(R.string.Cancel), null)
            .show();
        return true;
    }
}
