import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.5.4/index.ts';
import { assertEquals } from 'https://deno.land/std@0.170.0/testing/asserts.ts';

Clarinet.test({
  name: "Frontrun Search: Create Search Request",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const block = chain.mineBlock([
      Tx.contractCall('frontrun-search', 'create-frontrun-search', [
        types.ascii('STX123456'),
        types.ascii('TestContract'),
        types.utf8('Test search for potential frontrunning'),
        types.uint(5000000)
      ], deployer.address)
    ]);

    assertEquals(block.receipts.length, 1);
    assertEquals(block.height, 2);
    block.receipts[0].result.expectOk().expectUint(1);
  }
});

Clarinet.test({
  name: "Frontrun Search: Cancel Search Request",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const block = chain.mineBlock([
      Tx.contractCall('frontrun-search', 'create-frontrun-search', [
        types.ascii('STX123456'),
        types.ascii('TestContract'),
        types.utf8('Test search for potential frontrunning'),
        types.uint(5000000)
      ], deployer.address),
      Tx.contractCall('frontrun-search', 'cancel-frontrun-search', [
        types.uint(1)
      ], deployer.address)
    ]);

    assertEquals(block.receipts.length, 2);
    block.receipts[1].result.expectOk().expectBool(true);
  }
});