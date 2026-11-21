/// Switches for optional features. Change a value and rebuild the app.
class FeatureFlags {
  FeatureFlags._();

  // Enable or disable the surprise location feature.
  //
  // When false, none of it exists in the app: the surprise screen never
  // opens, the "Shared location" menu item is hidden, and the app never asks
  // for, reads or sends the location. The chat itself is unaffected.
  static const bool enableSurpriseLocation = true;

  // When true, the surprise screen opens every time the app starts (handy
  // while testing). When false, it opens by itself only once per person on
  // each device; after that, sharing is still possible from the menu under
  // "Shared location". Either way, nothing is shared without tapping
  // "Share My Location".
  static const bool showOnEveryAppOpen = true;
}
