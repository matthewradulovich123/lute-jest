/// <reference types="@rbxts/types" />
declare global {
  interface Matchers<R = void> {
    toBe(v: unknown): R;
    toEqual(v: unknown): R;
    toBeTruthy(): R;
    toBeFalsy(): R;
    toBeNil(): R;
    toBeDefined(): R;
    toBeGreaterThan(n: number): R;
    toBeLessThan(n: number): R;
    toContain(v: unknown): R;
    toThrow(msg?: string): R;
    toHaveBeenCalled(): R;
    toHaveBeenCalledTimes(n: number): R;
    toHaveBeenCalledWith(...args: unknown[]): R;
    never: Matchers<R>;
  }
  interface ExpectFn {
    <T>(value: T): Matchers;
  }
}
export const describe: (name: string, fn: () => void) => void;
export const it: (name: string, fn: () => void) => void;
export const test: (name: string, fn: () => void) => void;
export const expect: ExpectFn;
export const beforeEach: (fn: () => void) => void;
export const afterEach: (fn: () => void) => void;
export const beforeAll: (fn: () => void) => void;
export const afterAll: (fn: () => void) => void;
export const jest: {
  fn(): {
    (...args: unknown[]): unknown;
    mock: { calls: unknown[][]; results: unknown[] };
    mockReturnValue(v: unknown): unknown;
    mockImplementation(fn: (...args: unknown[]) => unknown): unknown;
    mockClear(): void;
  };
};
