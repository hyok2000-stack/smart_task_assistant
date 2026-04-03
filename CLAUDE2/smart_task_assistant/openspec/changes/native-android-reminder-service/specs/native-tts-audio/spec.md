## ADDED Requirements

### Requirement: TTS voice synthesis from native layer
The system SHALL use Android's native `TextToSpeech` API to play voice reminders, with parameter mapping identical to the Flutter `TTSService` and `HabitService` pitch/speed calculations.

#### Scenario: TTS plays with correct language
- **WHEN** a voice reminder is triggered
- **THEN** the TTS engine is initialized with `Locale.CHINA` (zh-CN) and speaks the reminder text

#### Scenario: Pitch matches Flutter layer voice types
- **WHEN** voiceType is "male" → pitch = 0.7, "female" → pitch = 1.3, "neutral" → pitch = 1.0
- **AND** voiceStyle adjusts: "gentle" → -0.1, "lively" → +0.1, "standard" → 0.0
- **THEN** the final pitch is `basePitch + styleAdjustment`, exactly matching the Flutter layer `_getPitch()` calculation

#### Scenario: Speech rate maps correctly
- **WHEN** speed is "slow" → rate = 0.8, "normal" → rate = 1.0, "fast" → rate = 1.4
- **THEN** these values produce equivalent perceived speed to the Flutter layer's (0.4, 0.5, 0.7) values (accounting for Android TTS rate scale difference)

#### Scenario: TTS initializes only once and is reused
- **WHEN** multiple reminders trigger in sequence
- **THEN** the TTS engine is initialized on first use and reused for subsequent calls, not re-created each time

### Requirement: Custom audio file playback
The system SHALL support playing custom voice files (local MP3/WAV) as an alternative to TTS, using `MediaPlayer` with alarm-level audio attributes.

#### Scenario: Custom voice file plays instead of TTS
- **WHEN** `customVoicePath` is not null and the file exists
- **THEN** TTS is skipped entirely and the custom audio file is played via MediaPlayer with `USAGE_ALARM` audio attribute (audible even in silent mode)

#### Scenario: Custom voice file not found
- **WHEN** `customVoicePath` is not null but the file does not exist
- **THEN** the system falls back to TTS with the reminder text

### Requirement: Reminder notification sound
The system SHALL play a notification sound via `MediaPlayer` when a reminder triggers, using `USAGE_ALARM` audio attribute to ensure audibility in silent/vibrate mode.

#### Scenario: Asset sound plays
- **WHEN** a reminder triggers and `assets/sounds/notification.mp3` has been copied to internal storage
- **THEN** the notification sound plays via MediaPlayer at alarm volume level

#### Scenario: Asset sound not available
- **WHEN** the custom notification sound file is not found
- **THEN** the system default notification sound is used (`RingtoneManager.getDefaultUri(TYPE_NOTIFICATION)`)

#### Scenario: Sound respects habit settings
- **WHEN** a habit has `sound_enabled = 0`
- **THEN** no notification sound is played for that habit's reminder

### Requirement: Vibration pattern
The system SHALL trigger a vibration pattern identical to the Flutter layer when a reminder fires.

#### Scenario: Standard vibration pattern
- **WHEN** a reminder triggers and vibration is enabled
- **THEN** vibration plays the pattern `[0, 300, 100, 300, 100, 300]` (3 pulses of 300ms with 100ms gaps), exactly matching the Flutter `Vibration.vibrate(pattern: [0, 300, 100, 300, 100, 300])`

#### Scenario: Vibration respects habit settings
- **WHEN** a habit has `vibration_enabled = 0`
- **THEN** no vibration is played for that habit's reminder

### Requirement: Playback sequencing
The system SHALL play sound, vibration, and TTS in a specific order with appropriate delays to prevent overlap.

#### Scenario: All three media play in sequence
- **WHEN** a reminder triggers with sound, vibration, and voice all enabled
- **THEN** sound plays first, vibration starts concurrently with sound, TTS/voice plays after a 1-second delay (to avoid overlapping with the notification sound)

#### Scenario: Only voice is enabled
- **WHEN** a reminder triggers with only `voice_enabled = 1`
- **THEN** TTS plays immediately with no delay, no sound or vibration
