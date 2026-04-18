import { describe, it, expect } from "@rbxts/jest-globals";
import { add, multiply } from "./math";

describe("math", () => {
  it("adds", () => {
    expect(add(2, 3)).toBe(5);
  });
  it("multiplies", () => {
    expect(multiply(4, 5)).toBe(20);
  });
});
