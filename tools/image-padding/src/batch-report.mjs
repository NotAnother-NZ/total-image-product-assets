import { PRICING_AS_OF } from './usage.mjs';

function formatMoney(value) { return '$' + value.toFixed(6); }
function formatTime(ms) {
  if (!Number.isFinite(ms) || ms < 0) return '--';
  const seconds = Math.round(ms / 1000);
  if (seconds < 60) return seconds + 's';
  const minutes = Math.floor(seconds / 60);
  return minutes + 'm ' + String(seconds % 60).padStart(2, '0') + 's';
}

export function aggregateUsage(reports) {
  const calls = reports.filter(r => r && r.source === 'openai-images-edits');
  const get = (r, key) => r.tokens?.[key];
  const totals = Object.fromEntries(['input', 'textInput', 'imageInput', 'imageOutput', 'total'].map(key => [
    key, calls.reduce((sum, r) => sum + (Number.isFinite(get(r, key)) ? get(r, key) : 0), 0)
  ]));
  const known = calls.filter(r => Number.isFinite(r.estimatedTotalUsd));
  const unknown = calls.length - known.length;
  return {
    apiCalls: calls.length, pricedCalls: known.length, unpricedCalls: unknown,
    tokens: totals,
    cost: {
      text: known.reduce((v, r) => v + (r.costsUsd?.textInput ?? 0), 0),
      imageInput: known.reduce((v, r) => v + (r.costsUsd?.imageInput ?? 0), 0),
      imageOutput: known.reduce((v, r) => v + (r.costsUsd?.imageOutput ?? 0), 0),
      pricedTotal: known.reduce((v, r) => v + r.estimatedTotalUsd, 0)
    },
    completeCost: unknown === 0,
    pricingAsOf: PRICING_AS_OF
  };
}

export function printTotalUsage(report) {
  console.log('\n========== OPENAI BATCH USAGE ==========');
  console.log('API requests with recorded usage:', report.apiCalls);
  console.log('Text input tokens:             ', report.tokens.textInput.toLocaleString());
  console.log('Image input tokens:            ', report.tokens.imageInput.toLocaleString());
  console.log('Image output tokens:           ', report.tokens.imageOutput.toLocaleString());
  console.log('TOTAL TOKENS (reported):       ', report.tokens.total.toLocaleString());
  console.log('Text input cost:               ', formatMoney(report.cost.text));
  console.log('Image input cost:              ', formatMoney(report.cost.imageInput));
  console.log('Image output cost:             ', formatMoney(report.cost.imageOutput));
  const qualifier = report.completeCost ? '' : ' (PARTIAL: unknown usage on ' + report.unpricedCalls + ' call(s))';
  console.log('TOTAL ESTIMATED API COST:      ', formatMoney(report.cost.pricedTotal) + ' USD' + qualifier);
  console.log('Rates as of', report.pricingAsOf, '(not an invoice)');
  console.log('========================================\n');
}

export function createProgress(total, initial = 0) {
  let done = initial;
  const started = Date.now();
  let lastLineLength = 0;
  const width = 24;
  function render(label = '') {
    const fraction = total ? done / total : 1;
    const blocks = Math.round(fraction * width);
    const bar = '#'.repeat(blocks) + '-'.repeat(width - blocks);
    const percent = String(Math.round(fraction * 100)).padStart(3);
    const eta = done > initial && done < total ? (Date.now() - started) * (total - done) / (done - initial) : null;
    const current = '[' + bar + '] ' + done + '/' + total + ' ' + percent + '% ETA ' + formatTime(eta) + ' ' + label;
    process.stdout.write('\r' + current.padEnd(lastLineLength, ' '));
    lastLineLength = Math.max(lastLineLength, current.length);
    if (done >= total) process.stdout.write('\n');
  }
  return {
    step(label = '') { done++; render(label); },
    update(label = '') { render(label); },
    note(message) {
      if (lastLineLength) process.stdout.write('\r' + ' '.repeat(lastLineLength) + '\r');
      console.log(message);
      render();
    },
    close() { if (done < total) process.stdout.write('\n'); }
  };
}
