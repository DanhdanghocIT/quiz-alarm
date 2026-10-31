import os
import wave
import math
import struct

def generate_alarm_wav(filepath="QuizAlarm/alarm.wav"):
    os.makedirs(os.path.dirname(filepath), exist_ok=True)

    sample_rate = 22050
    duration_seconds = 15.0
    total_samples = int(sample_rate * duration_seconds)
    amplitude = 28000  # 16-bit PCM max is 32767

    # Pattern: Chu kỳ 1 giây gồm 4 tiếng bíp nhanh (xen kẽ 1000Hz và 1400Hz) rồi nghỉ
    frames = bytearray()

    for i in range(total_samples):
        t = i / sample_rate
        cycle_pos = t % 1.0

        # 4 tiếng bíp trong 0.6 giây đầu của mỗi chu kỳ 1 giây
        beep_index = int(cycle_pos / 0.15)
        pos_in_beep = cycle_pos % 0.15

        if cycle_pos < 0.60 and pos_in_beep < 0.10:
            freq = 1000.0 if (beep_index % 2 == 0) else 1400.0
            # Làm mượt 5ms đầu và cuối mỗi tiếng bíp để tránh tiếng click
            fade_len = 0.005
            if pos_in_beep < fade_len:
                env = pos_in_beep / fade_len
            elif pos_in_beep > (0.10 - fade_len):
                env = (0.10 - pos_in_beep) / fade_len
            else:
                env = 1.0

            # Cộng sóng cơ bản và họa âm bậc 3 để âm báo sắc, dễ đánh thức
            val = 0.8 * math.sin(2.0 * math.pi * freq * t) + 0.2 * math.sin(2.0 * math.pi * (freq * 3.0) * t)
            sample = int(amplitude * env * val)
            sample = max(-32767, min(32767, sample))
        else:
            sample = 0

        frames.extend(struct.pack("<h", sample))

    with wave.open(filepath, "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(frames)

    print(f"Created {filepath} ({duration_seconds}s, {sample_rate}Hz)")

if __name__ == "__main__":
    generate_alarm_wav()