import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class ClassicFaceApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        return [ new ClassicFaceView() ];
    }

    // Called when the user changes settings in Garmin Connect / Connect IQ app
    function onSettingsChanged() {
        WatchUi.requestUpdate();
    }
}
