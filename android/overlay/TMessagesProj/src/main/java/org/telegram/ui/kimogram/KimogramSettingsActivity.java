package org.telegram.ui.kimogram;

import android.content.Context;
import android.view.View;

import org.telegram.messenger.AndroidUtilities;
import org.telegram.messenger.NotificationCenter;
import org.telegram.messenger.kimogram.KimogramAutoProxy;
import org.telegram.messenger.kimogram.KimogramConfig;
import org.telegram.ui.Components.RecyclerListView;
import org.telegram.ui.Components.UItem;
import org.telegram.ui.Components.UniversalAdapter;
import org.telegram.ui.Components.UniversalFragment;
import org.telegram.ui.ProxyListActivity;

import java.util.ArrayList;

import static org.telegram.messenger.kimogram.KimogramConfig.t;

/** Kimogram: "Настройки Kimogram", every switch of the mod in one place. */
public class KimogramSettingsActivity extends UniversalFragment implements NotificationCenter.NotificationCenterDelegate {

    private static final int ID_AUTO_PROXY = 1;
    private static final int ID_PROXY_LIST = 2;
    private static final int ID_GHOST_READ = 10;
    private static final int ID_GHOST_ONLINE = 11;
    private static final int ID_GHOST_TYPING = 12;
    private static final int ID_GHOST_STORIES = 13;
    private static final int ID_HIDE_SPONSORED = 20;
    private static final int ID_HIDE_STORIES_BAR = 21;
    private static final int ID_HIDE_PREMIUM = 22;
    private static final int ID_CONFIRM_CALLS = 30;

    @Override
    protected boolean useSimpleActionBar() {
        return true;
    }

    @Override
    public View createView(Context context) {
        setHasOwnBackground(true);
        fragmentView = super.createView(context);
        listView.setSections();
        listView.setSectionsDrawBackground(true);
        return fragmentView;
    }

    @Override
    protected RecyclerListView getListViewForSimpleGlass() {
        return listView;
    }

    @Override
    public boolean isSupportEdgeToEdge() {
        return true;
    }

    @Override
    public boolean onFragmentCreate() {
        NotificationCenter.getGlobalInstance().addObserver(this, NotificationCenter.proxySettingsChanged);
        return super.onFragmentCreate();
    }

    @Override
    public void onFragmentDestroy() {
        NotificationCenter.getGlobalInstance().removeObserver(this, NotificationCenter.proxySettingsChanged);
        super.onFragmentDestroy();
    }

    @Override
    public void didReceivedNotification(int id, int account, Object... args) {
        if (id == NotificationCenter.proxySettingsChanged && listView != null) {
            listView.adapter.update(true);
        }
    }

    @Override
    public void onResume() {
        super.onResume();
        if (listView != null) {
            listView.adapter.update(false);
        }
    }

    @Override
    protected CharSequence getTitle() {
        return t("Настройки Kimogram", "Kimogram Settings");
    }

    @Override
    protected void fillItems(ArrayList<UItem> items, UniversalAdapter adapter) {
        final boolean store = KimogramConfig.isStoreEdition();

        items.add(UItem.asHeader(t("Прокси", "Proxy")));
        items.add(UItem.asCheck(ID_AUTO_PROXY, t("Авто-прокси Kimogram", "Kimogram auto-proxy")).setChecked(KimogramAutoProxy.getInstance().isEnabled()));
        items.add(UItem.asButton(ID_PROXY_LIST, t("Свой прокси", "Your own proxy")));
        items.add(UItem.asShadow(KimogramAutoProxy.getInstance().getStatus() + "\n" + t(
            "Если Telegram не открывается, Kimogram сам найдёт быстрый бесплатный прокси и подключится через него. Свой прокси, добавленный вручную, он не трогает.",
            "If Telegram can't be reached, Kimogram finds a fast free proxy and connects through it. A proxy you added yourself is never touched.")));

        if (!store) {
            items.add(UItem.asHeader(t("Режим призрака", "Ghost mode")));
            items.add(UItem.asCheck(ID_GHOST_READ, t("Не отмечать прочитанным", "Don't mark as read")).setChecked(KimogramConfig.get(KimogramConfig.GHOST_READ)));
            items.add(UItem.asCheck(ID_GHOST_ONLINE, t("Не показывать «в сети»", "Hide \"online\"")).setChecked(KimogramConfig.get(KimogramConfig.GHOST_ONLINE)));
            items.add(UItem.asCheck(ID_GHOST_TYPING, t("Не показывать «печатает»", "Hide \"typing\"")).setChecked(KimogramConfig.get(KimogramConfig.GHOST_TYPING)));
            items.add(UItem.asCheck(ID_GHOST_STORIES, t("Смотреть истории незаметно", "View stories unseen")).setChecked(KimogramConfig.get(KimogramConfig.GHOST_STORIES)));
            items.add(UItem.asShadow(t(
                "Собеседники не увидят, что вы прочитали сообщения, были в сети, печатали или смотрели их истории.",
                "Others won't see that you read their messages, were online, typed or watched their stories.")));
        }

        items.add(UItem.asHeader(t("Интерфейс", "Interface")));
        if (!store) {
            items.add(UItem.asCheck(ID_HIDE_SPONSORED, t("Скрыть рекламу в каналах", "Hide sponsored messages")).setChecked(KimogramConfig.get(KimogramConfig.HIDE_SPONSORED)));
        }
        items.add(UItem.asCheck(ID_HIDE_STORIES_BAR, t("Скрыть истории над чатами", "Hide stories above chats")).setChecked(KimogramConfig.get(KimogramConfig.HIDE_STORIES_BAR)));
        items.add(UItem.asCheck(ID_HIDE_PREMIUM, t("Скрыть Premium, Stars и подарки в настройках", "Hide Premium, Stars and gifts in settings")).setChecked(KimogramConfig.get(KimogramConfig.HIDE_PREMIUM_ROWS)));
        items.add(UItem.asShadow(null));

        items.add(UItem.asHeader(t("Звонки", "Calls")));
        items.add(UItem.asCheck(ID_CONFIRM_CALLS, t("Спрашивать перед звонком", "Confirm before calling")).setChecked(KimogramConfig.get(KimogramConfig.CONFIRM_CALLS)));
        items.add(UItem.asShadow(t("Защита от случайного звонка по нажатию на трубку.", "Protects from calling someone by accident.")));
    }

    @Override
    protected void onClick(UItem item, View view, int position, float x, float y) {
        switch (item.id) {
            case ID_AUTO_PROXY:
                KimogramAutoProxy.getInstance().setEnabled(!KimogramAutoProxy.getInstance().isEnabled());
                break;
            case ID_PROXY_LIST:
                presentFragment(new ProxyListActivity());
                return;
            case ID_GHOST_READ:
                KimogramConfig.toggle(KimogramConfig.GHOST_READ);
                break;
            case ID_GHOST_ONLINE:
                KimogramConfig.toggle(KimogramConfig.GHOST_ONLINE);
                break;
            case ID_GHOST_TYPING:
                KimogramConfig.toggle(KimogramConfig.GHOST_TYPING);
                break;
            case ID_GHOST_STORIES:
                KimogramConfig.toggle(KimogramConfig.GHOST_STORIES);
                break;
            case ID_HIDE_SPONSORED:
                KimogramConfig.toggle(KimogramConfig.HIDE_SPONSORED);
                break;
            case ID_HIDE_STORIES_BAR:
                KimogramConfig.toggle(KimogramConfig.HIDE_STORIES_BAR);
                NotificationCenter.getInstance(currentAccount).postNotificationName(NotificationCenter.storiesUpdated);
                break;
            case ID_HIDE_PREMIUM:
                KimogramConfig.toggle(KimogramConfig.HIDE_PREMIUM_ROWS);
                break;
            case ID_CONFIRM_CALLS:
                KimogramConfig.toggle(KimogramConfig.CONFIRM_CALLS);
                break;
            default:
                return;
        }
        AndroidUtilities.runOnUIThread(() -> {
            if (listView != null) {
                listView.adapter.update(true);
            }
        });
    }

    @Override
    protected boolean onLongClick(UItem item, View view, int position, float x, float y) {
        return false;
    }
}
