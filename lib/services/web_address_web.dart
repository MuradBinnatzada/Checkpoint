import 'dart:js_interop';

@JS('history')
external _History get _history;

extension type _History._(JSObject _) implements JSObject {
  external void replaceState(JSAny? data, String unused, String url);
}

/// Replaces the address the browser shows, without a reload or a new history
/// entry.
void replaceWebAddress(Uri address) =>
    _history.replaceState(null, '', address.toString());
