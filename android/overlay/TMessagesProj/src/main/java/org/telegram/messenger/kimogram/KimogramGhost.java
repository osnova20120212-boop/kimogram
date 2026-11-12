package org.telegram.messenger.kimogram;

import org.telegram.tgnet.TLObject;
import org.telegram.tgnet.TLRPC;
import org.telegram.tgnet.tl.TL_account;
import org.telegram.tgnet.tl.TL_stories;

/**
 * Kimogram ghost mode, applied to every request just before it is sent
 * (ConnectionsManager.sendRequestInternal, on the stage queue).
 */
public final class KimogramGhost {

    private KimogramGhost() {
    }

    /** Returns true when the request must not be sent at all. May change the request. */
    public static boolean intercept(TLObject request) {
        if (request == null) {
            return false;
        }
        if (request instanceof TL_account.updateStatus) {
            if (KimogramConfig.get(KimogramConfig.GHOST_ONLINE)) {
                ((TL_account.updateStatus) request).offline = true;
            }
            return false;
        }
        if (request instanceof TLRPC.TL_messages_readHistory
                || request instanceof TLRPC.TL_channels_readHistory
                || request instanceof TLRPC.TL_messages_readDiscussion) {
            return KimogramConfig.get(KimogramConfig.GHOST_READ);
        }
        if (request instanceof TLRPC.TL_messages_setTyping) {
            return KimogramConfig.get(KimogramConfig.GHOST_TYPING);
        }
        if (request instanceof TL_stories.TL_stories_readStories
                || request instanceof TL_stories.TL_stories_incrementStoryViews) {
            return KimogramConfig.get(KimogramConfig.GHOST_STORIES);
        }
        return false;
    }
}
