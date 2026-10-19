// Changing the web app's address bar without reloading the page. Elsewhere there
// is no address bar, and this does nothing.
export 'web_address_stub.dart'
    if (dart.library.js_interop) 'web_address_web.dart';
