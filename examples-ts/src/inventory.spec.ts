import { describe, it, expect, beforeEach } from "@rbxts/jest-globals";
import { Inventory } from "./inventory";

describe("Inventory", () => {
	let inv: Inventory;
	beforeEach(() => { inv = new Inventory(); });

	it("starts empty", () => { expect(inv.total()).toBe(0); });
	it("adds items", () => {
		inv.add("sword");
		inv.add("sword", 2);
		expect(inv.count("sword")).toBe(3);
		expect(inv.total()).toBe(3);
	});
	it("removes items", () => {
		inv.add("potion", 5);
		inv.remove("potion", 2);
		expect(inv.count("potion")).toBe(3);
	});
	it("returns 0 for missing items", () => {
		expect(inv.count("ghost")).toBe(0);
	});
	it("delete item when qty <= 0", () => {
		inv.add("apple", 2);
		inv.remove("apple", 5);
		expect(inv.count("apple")).toBe(0);
		expect(inv.total()).toBe(0);
	});
});
