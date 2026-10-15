import test from 'node:test';
import assert from 'node:assert/strict';
import { groupEntries, escapeXml } from '../src/batch-review.mjs';
import { aggregateUsage, printTotalUsage } from '../src/batch-report.mjs';

test('contact sheet groups ready/applied images separately from failures and skips', () => {
  const sample = { entries: [
    { slug: 'a', imageItemId: 'one', status: 'ready' },
    { slug: 'b', imageItemId: 'two', status: 'skipped' },
    { slug: 'c', imageItemId: 'three', status: 'failed' },
    { slug: 'd', imageItemId: 'four', status: 'applied' }
  ] };
  const grouped = groupEntries(sample);
  assert.deepEqual(grouped.ready.map(x => x.imageItemId), ['one', 'four']);
  assert.deepEqual(grouped.unresolved.map(x => x.imageItemId), ['two', 'three']);
});

test('invalid summary cannot result in silently duplicated image review', () => {
  assert.throws(() => groupEntries({ entries: [{ slug:'a', imageItemId:'same', status:'ready' },
    { slug:'b', imageItemId:'same', status:'skipped' }] }), /Duplicate image ID/);
  assert.throws(() => groupEntries({ entries: null }), /Missing batch summary/);
});

test('review sheet safely escapes product names containing markup', () => {
  assert.equal(escapeXml('A & B <C> "D"'), 'A &amp; B &lt;C&gt; &quot;D&quot;');
});

test('unreceipted OpenAI calls cause a visibly partial total cost', () => {
  const usage = aggregateUsage([{
    source:'openai-images-edits',
    tokens:{input:30,textInput:10,imageInput:20,imageOutput:100,total:130},
    costsUsd:{textInput:0.00005,imageInput:0.00016,imageOutput:0.003},
    estimatedTotalUsd:0.00321
  }]);
  assert.equal(usage.completeCost, true);
  usage.unknownApiRequests = 1;
  usage.completeCost = usage.completeCost && usage.unknownApiRequests === 0;
  const log = [];
  const previous = console.log;
  try {
    console.log = (...args) => log.push(args.join(' '));
    printTotalUsage(usage);
  } finally {
    console.log = previous;
  }
  assert.match(log.join('\n'), /PARTIAL: possible unknown cost for 1 call\(s\)/);
  assert.equal(usage.completeCost, false);
});
