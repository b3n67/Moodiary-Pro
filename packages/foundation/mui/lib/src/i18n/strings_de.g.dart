///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:slang/generated.dart';
import 'strings.g.dart';

// Path: <root>
class MuiLocalizationsDataDe extends MuiLocalizationsData with BaseTranslations<MuiLocale, MuiLocalizationsData> {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [MuiLocale.build] is preferred.
	MuiLocalizationsDataDe({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<MuiLocale, MuiLocalizationsData>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  _meta = meta ?? TranslationMetadata(
		    locale: MuiLocale.de,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ),
		  super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver);

	/// Metadata for the translations of <de>.
	final TranslationMetadata<MuiLocale, MuiLocalizationsData> _meta;
	@override TranslationMetadata<MuiLocale, MuiLocalizationsData> get $meta => _meta;

	late final MuiLocalizationsDataDe _root = this; // ignore: unused_field

	@override 
	MuiLocalizationsDataDe $copyWith({TranslationMetadata<MuiLocale, MuiLocalizationsData>? meta}) => MuiLocalizationsDataDe(meta: meta ?? this.$meta);

	// Translations
	@override String get ok => 'OK';
	@override String get cancel => 'Abbrechen';
	@override String get back => 'Zurück';
	@override String get colorPickerTitle => 'Farbe wählen';
	@override String get toastLoading => 'Wird geladen';
	@override String get toastSuccess => 'Erfolg';
	@override String get toastError => 'Fehler';
	@override String get configured => 'Konfiguriert';
	@override String get notConfigured => 'Nicht konfiguriert';
	@override String get input => 'Eingeben';
	@override String get save => 'Speichern';
}
