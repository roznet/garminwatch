import Toybox.Complications;
import Toybox.Lang;
import Toybox.WatchUi;

// Press and hold on a data slot to open the matching native glance.
// On a watch face onPress is a touch-and-hold: onTap only fires in the watch's face edit mode,
// so a quick tap never reaches us.
class InstrumentDelegate extends WatchUi.WatchFaceDelegate {

    private var mView as WatchFaceView;

    function initialize(view as WatchFaceView) {
        WatchFaceDelegate.initialize();
        mView = view;
    }

    function onPress(clickEvent as WatchUi.ClickEvent) as Boolean {
        var coordinates = clickEvent.getCoordinates();
        var id = mView.complicationAt(coordinates[0], coordinates[1]);
        if (id == null) {
            return false;
        }
        try {
            Complications.exitTo(id);
            return true;
        } catch (e) {
            // Some complications cannot be launched; let the system handle the press instead
            return false;
        }
    }

}
