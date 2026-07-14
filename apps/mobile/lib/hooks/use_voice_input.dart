import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../features/settings/state/settings_cubit.dart';
import '../l10n/app_localizations.dart';
import '../services/bridge_service.dart';
import '../services/voice_input_service.dart';

/// Result record returned by [useVoiceInput].
typedef VoiceInputResult = ({
  bool isAvailable,
  bool isRecording,
  bool isTranscribing,
  void Function() toggle,
});

/// Manages [VoiceInputService] lifecycle: initialization, start/stop, and
/// disposal.
///
/// The [controller] is updated in real-time with recognized speech text.
/// Speech locale is read from [SettingsCubit].
VoiceInputResult useVoiceInput(TextEditingController controller) {
  final context = useContext();
  final voiceInput = useMemoized(() => VoiceInputService());
  final isAvailable = useState(false);
  final isRecording = useState(false);
  final isTranscribing = useState(false);

  useEffect(() {
    voiceInput.initialize().then((available) {
      if (context.mounted) isAvailable.value = available;
    });
    return voiceInput.dispose;
  }, const []);

  Future<void> toggleAsync() async {
    if (isTranscribing.value) return;
    if (isRecording.value) {
      isRecording.value = false;
      isTranscribing.value = true;
      try {
        final localeId = context.read<SettingsCubit>().state.speechLocaleId;
        final text = await voiceInput.stopAndTranscribe(
          bridge: context.read<BridgeService>(),
          localeId: localeId.isNotEmpty ? localeId : 'ru-RU',
        );
        if (context.mounted && text.isNotEmpty) {
          controller.value = composeVoiceInputValue(controller.value, text);
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).voiceTranscriptionFailed,
              ),
            ),
          );
        }
      } finally {
        if (context.mounted) isTranscribing.value = false;
      }
    } else {
      HapticFeedback.mediumImpact();
      try {
        await voiceInput.startRecording();
        if (context.mounted) isRecording.value = voiceInput.isRecording;
      } catch (_) {
        if (context.mounted) {
          isRecording.value = false;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).voiceTranscriptionFailed,
              ),
            ),
          );
        }
      }
    }
  }

  void toggle() => unawaited(toggleAsync());

  return (
    isAvailable: isAvailable.value,
    isRecording: isRecording.value,
    isTranscribing: isTranscribing.value,
    toggle: toggle,
  );
}

@visibleForTesting
TextEditingValue composeVoiceInputValue(
  TextEditingValue baseValue,
  String recognizedText,
) {
  final baseText = baseValue.text;
  final selection = baseValue.selection;
  final rawStart = selection.isValid ? selection.start : baseText.length;
  final rawEnd = selection.isValid ? selection.end : baseText.length;
  final start = _clampOffset(rawStart, baseText.length);
  final end = _clampOffset(rawEnd, baseText.length);
  final insertStart = start < end ? start : end;
  final insertEnd = start < end ? end : start;
  final nextText = baseText.replaceRange(
    insertStart,
    insertEnd,
    recognizedText,
  );
  final cursorOffset = insertStart + recognizedText.length;

  return TextEditingValue(
    text: nextText,
    selection: TextSelection.collapsed(offset: cursorOffset),
  );
}

int _clampOffset(int offset, int max) => offset.clamp(0, max).toInt();
