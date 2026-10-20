export const SIMULATION_HZ = 60;
export const MAX_CATCH_UP_STEPS = 5;
export const MAX_RENDER_FPS = 240;
export const NATIVE_FRAME_RATE = 0;
export const UNCAPPED_FRAME_RATE = -1;
const DEADLINE_EPSILON = 1e-9;

export function parseFrameRate(value = "60") {
  if (value === "native") {
    return NATIVE_FRAME_RATE;
  }
  if (value === "uncapped") {
    return UNCAPPED_FRAME_RATE;
  }
  const rate = Number(value);
  if (
    !/^\d+$/.test(String(value)) ||
    !Number.isInteger(rate) ||
    rate < 1 ||
    rate > MAX_RENDER_FPS
  ) {
    throw new Error("Frame rate must be an integer from 1 to 240, native, or uncapped.");
  }
  return rate;
}

// Rendering deadlines never change the simulation clock or accumulate draw debt.
export class FrameClock {
  elapsed = 0;
  accumulator = 0;
  nextDraw = 0;

  advance(delta) {
    const bounded = Math.max(0, Math.min(delta, 0.1));
    this.elapsed += bounded;
    this.accumulator = Math.min(this.accumulator + bounded, MAX_CATCH_UP_STEPS / SIMULATION_HZ);
  }

  take(fps, displayOpportunity = true) {
    const steps = Math.min(
      Math.floor((this.accumulator + DEADLINE_EPSILON) * SIMULATION_HZ),
      MAX_CATCH_UP_STEPS,
    );
    this.accumulator = Math.max(0, this.accumulator - steps / SIMULATION_HZ);
    const render =
      fps === UNCAPPED_FRAME_RATE ||
      (fps === NATIVE_FRAME_RATE
        ? displayOpportunity
        : this.elapsed + DEADLINE_EPSILON >= this.nextDraw);
    if (render && fps > 0) {
      this.nextDraw = (Math.floor((this.elapsed + DEADLINE_EPSILON) * fps) + 1) / fps;
    }
    return { steps, render };
  }

  delay(fps) {
    const tick = 1 / SIMULATION_HZ - this.accumulator;
    const draw = fps <= 0 ? Infinity : this.nextDraw - this.elapsed;
    return Math.max(1, Math.min(tick, draw) * 1000);
  }
}
