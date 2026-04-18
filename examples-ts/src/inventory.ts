export interface Item { id: string; qty: number }

export class Inventory {
	private items: Item[] = [];
	add(id: string, qty: number = 1): void {
		const existing = this.items.find((it) => it.id === id);
		if (existing) existing.qty += qty;
		else this.items.push({ id, qty });
	}
	remove(id: string, qty: number = 1): boolean {
		const idx = this.items.findIndex((it) => it.id === id);
		if (idx === -1) return false;
		this.items[idx].qty -= qty;
		if (this.items[idx].qty <= 0) this.items.remove(idx);
		return true;
	}
	count(id: string): number {
		const it = this.items.find((it) => it.id === id);
		return it ? it.qty : 0;
	}
	total(): number {
		let n = 0;
		for (const it of this.items) n += it.qty;
		return n;
	}
}
