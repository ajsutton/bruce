# House Voice Options

## Status

Decision note only. No speech functionality is currently approved for implementation.

## Goal

Give the house a consistent spoken identity for status messages, confirmations, warnings, and
eventual voice interactions.

The preferred solution should:

- have no ongoing usage cost;
- ideally use entirely free software and services;
- work without an Internet connection;
- sound pleasant when delivering frequent, short household messages;
- support iPhone and Mac initially;
- allow the same identity to be used by Home Assistant and household speakers eventually; and
- keep Siri, HomeKit, and the house voice conceptually distinct.

## Options

### 1. Selected Apple system voice

Use `AVSpeechSynthesizer` and explicitly assign an installed `AVSpeechSynthesisVoice` to every
utterance. The app can enumerate voices, filter by locale and quality, preview them, and persist
the selected identifier instead of using the device's default voice.

Apple offers default, enhanced, and premium speech voice qualities. Enhanced and premium
voices are free but may require the user to download them in system settings.

Advantages:

- no per-use or ongoing cost;
- entirely on-device;
- high-quality synthesis with minimal implementation;
- immediate response and graceful offline operation; and
- rate, pitch, volume, and wording can be tuned for a consistent delivery style.

Limitations:

- an app cannot request "the currently selected Siri voice" as a supported abstraction;
- the exact voices installed and exposed to apps can vary by device, platform, locale, and OS;
- the chosen voice may need to be installed separately on each family member's device;
- the voice is not truly unique to the house; and
- Home Assistant on Linux cannot directly synthesize with Apple's voices.

This option can still feel distinctive when combined with a short house sound, restrained
prosody, and consistent language.

References:

- [AVSpeechSynthesisVoice](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoice)
- [AVSpeechSynthesisVoiceQuality](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoicequality)

### 2. Existing Piper voice

Run Piper locally alongside Home Assistant using an existing, suitably licensed voice model.
Adjust speaking speed and variability, then add the house sound and language style around it.

Advantages:

- no per-use cost;
- fully local and available during an Internet outage;
- one central voice can serve Home Assistant, Apple devices, tablets, and speakers;
- lightweight CPU inference; and
- direct Home Assistant support through the Wyoming protocol.

Limitations:

- not unique unless the presentation around it supplies the identity;
- generally less expressive than leading hosted services;
- available Australian voices may be limited; and
- the engine and each selected voice model have licences that must be checked separately.

This is the lowest-risk way to test whether central local speech is useful before recording or
training anything.

References:

- [Piper](https://github.com/OHF-Voice/piper1-gpl)
- [Home Assistant Piper integration](https://www.home-assistant.io/integrations/piper)

### 3. Custom Piper voice

Record a consenting speaker and fine-tune a Piper checkpoint on those recordings. Export the
result as an ONNX model and run it through the same local Piper service.

Piper does not design a new voice from a written description. The identity comes from the
recorded speaker, so a source voice and the right to use it are required.

The dataset consists of one audio file per utterance plus an exact transcript:

```text
house_0001.wav|The air conditioning is set to twenty-three degrees.
house_0002.wav|The garage door is still open.
```

A sensible staged dataset would be:

1. Record 20 to 30 minutes to prove the training pipeline and evaluate the identity.
2. Test at least 100 representative household phrases.
3. If the voice works, expand to approximately two hours of clean speech for an initial
   household-notification model.
4. Record more material only when testing demonstrates a pronunciation or generalisation need.

The recording script should cover names, rooms, manufacturers, numbers, times, temperatures,
weather, questions, confirmations, and warnings. Consistent microphone position, room sound,
gain, delivery, and exact transcripts matter more than expensive recording equipment.

Training is most practical on a Linux machine with a discrete GPU. Piper documents successful
training with as little as 8 GB of VRAM, while recommending fine-tuning an existing checkpoint
instead of training from scratch. Inference can then run on an ordinary CPU.

Advantages:

- a genuinely house-specific voice;
- no ongoing cost after training;
- fully local operation;
- one voice across every client and speaker; and
- complete control over vocabulary and future retraining.

Limitations:

- recording and cleaning the dataset is a meaningful production task;
- the house will sound recognisably like the source speaker;
- obtaining a distinctive non-household performance may cost money;
- training requires suitable compute, even if only temporarily;
- pronunciation and audio quality require iterative evaluation; and
- checkpoint, dataset, engine, and resulting-model licensing must be recorded.

Reference:

- [Piper voice training](https://github.com/OHF-Voice/piper1-gpl/blob/main/docs/TRAINING.md)

### 4. Prerecorded house phrases

Record or synthesize a finite library of common messages and package or centrally serve the
audio. Dynamic values can use carefully assembled fragments or fall back to another
synthesizer.

Advantages:

- maximum control over performance;
- no runtime synthesis cost;
- works offline; and
- excellent for recurring confirmations, warnings, and identity sounds.

Limitations:

- does not handle arbitrary text naturally;
- fragment assembly can sound unnatural; and
- the phrase library becomes an asset-maintenance task.

This is useful as a complement to another option, particularly for signature greetings and
high-priority warnings.

### 5. Apple custom speech-synthesis provider

Bundle a local synthesis model in an Apple speech-synthesis provider extension. Its voices can
be made available to `AVSpeechSynthesizer` and system accessibility features.

Advantages:

- custom voice runs directly on Apple devices;
- no ongoing service cost; and
- deeper integration with Apple's speech facilities.

Limitations:

- Apple prohibits network access from the synthesizer extension;
- the model and inference runtime must be shipped and supported on every Apple platform;
- it does not solve central Home Assistant or speaker synthesis by itself; and
- substantially more complexity than playing audio returned by a local Piper service.

This is not justified unless system-wide availability of the house voice becomes a concrete
requirement.

Reference:

- [Creating a custom speech synthesizer](https://developer.apple.com/documentation/avfaudio/creating-a-custom-speech-synthesizer)

### 6. Hosted designed or cloned voice

Services such as ElevenLabs and eligible OpenAI accounts can provide designed or cloned voices
with excellent quality and low integration effort.

Advantages:

- strongest route to a distinctive, polished identity;
- expressive delivery; and
- no local training hardware.

Limitations:

- ongoing usage cost;
- Internet and vendor dependency;
- household text leaves the home;
- service terms and availability can change; and
- API credentials require a trusted backend.

This conflicts with the preferred cost and privacy model. It remains useful only as a temporary
quality benchmark or a fallback if local synthesis proves unacceptable.

## Comparison

| Option | Ongoing cost | Fully local | Truly unique | Central HA voice | Initial effort |
| --- | --- | --- | --- | --- | --- |
| Selected Apple voice | None | Yes | No | No | Very low |
| Existing Piper voice | None | Yes | No | Yes | Low |
| Custom Piper voice | None | Yes | Yes, within source voice limits | Yes | High |
| Prerecorded phrases | None | Yes | Potentially | Yes | Medium |
| Apple provider extension | None | Yes | Potentially | No | Very high |
| Hosted custom voice | Yes | No | Yes | Yes | Low |

## Speech recognition

Speech input is separate from the house voice. On iOS and macOS 26, the app can use Apple's
`SpeechAnalyzer` and `SpeechTranscriber` for live, on-device transcription. The resulting text
can be sent to Home Assistant for interpretation and execution, after which the response is
spoken using the selected house voice.

The initial interaction should be push-to-talk. Ordinary iPhone apps do not have a general
purpose, permanently listening Siri-style wake-word facility.

Reference:

- [Apple Speech framework](https://developer.apple.com/documentation/speech)

## Recommended progression

1. Use an explicitly selected Apple enhanced or premium Australian English voice in the native
   apps.
2. Define the house's wording, pacing, warning style, and short identity sound independently of
   the synthesizer.
3. Run an existing Piper voice locally and compare it against the selected Apple voice using a
   representative phrase set.
4. Only if a central, unique voice proves valuable, record a 20-to-30-minute custom Piper
   prototype.
5. Expand the dataset to approximately two hours only after the prototype voice survives regular
   household listening tests.

The application should not commit to a synthesis-provider abstraction until the first speech
use case is implemented. The initial implementation can introduce the smallest boundary needed
to support its actual fallback behaviour.

## Decision criteria for listening tests

Candidate voices should be evaluated on:

- clarity from another room and over ordinary speakers;
- Australian pronunciation of household vocabulary;
- natural delivery of short fragments, numbers, and temperatures;
- consistency between calm status messages and urgent warnings;
- latency;
- fatigue and irritation after repeated use;
- behaviour during Internet or Home Assistant outages; and
- acceptance by every regular household user.
