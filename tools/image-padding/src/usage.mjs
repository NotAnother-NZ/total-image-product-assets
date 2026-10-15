// Standard (non-Batch) GPT Image 2.5 rates for direct /v1/images/edits calls.
// Verified against https://developers.openai.com/api/docs/pricing on 2026-10-15.
// USD per 1 million tokens. The direct Images API has no cached-input discount.
export const PRICING_AS_OF = '2026-10-15';
export const MODEL_RATES = Object.freeze({
  'gpt-image-2.5-sunburst': Object.freeze({ textInput: 5, imageInput: 8, imageOutput: 30 }),
  'gpt-image-2.5-flare': Object.freeze({ textInput: 5, imageInput: 8, imageOutput: 30 })
});
const perMillion = 1_000_000;
const wholeToken = value => Number.isSafeInteger(value) && value >= 0 ? value : null;
const shown = value => value === null ? 'unavailable' : value.toLocaleString('en-US');
const dollars = value => value === null ? 'unavailable' : '$' + value.toFixed(8);

export function imageEditUsageReport(usage, model) {
  const rates = MODEL_RATES[model];
  if (!rates) throw new Error('No verified pricing for image model: ' + model);

  const input = wholeToken(usage?.input_tokens);
  const textInput = wholeToken(usage?.input_tokens_details?.text_tokens);
  const imageInput = wholeToken(usage?.input_tokens_details?.image_tokens);
  const imageOutput = wholeToken(usage?.output_tokens);
  const apiTotal = wholeToken(usage?.total_tokens);
  const total = apiTotal ?? (input !== null && imageOutput !== null ? input + imageOutput : null);
  const warning = [];

  if (!usage) {
    warning.push('The OpenAI response contained no usage object; actual usage and cost are unknown.');
  } else if (input === null || textInput === null || imageInput === null ||
             imageOutput === null || total === null) {
    warning.push('The API omitted one or more required token counts; a reliable cost cannot be calculated.');
  } else if (textInput + imageInput !== input || input + imageOutput !== total) {
    warning.push('Token subtotals do not match the total; a reliable cost cannot be calculated.');
  }

  const valid = usage && warning.length === 0;
  const costs = valid ? {
    textInput: textInput * rates.textInput / perMillion,
    imageInput: imageInput * rates.imageInput / perMillion,
    imageOutput: imageOutput * rates.imageOutput / perMillion
  } : null;
  const estimatedTotalUsd = costs
    ? costs.textInput + costs.imageInput + costs.imageOutput
    : null;

  return {
    source: 'openai-images-edits',
    model,
    pricingAsOf: PRICING_AS_OF,
    pricingUnit: 'USD per million tokens, Standard API (non-Batch)',
    ratesUsdPerMillion: rates,
    tokens: { input, textInput, imageInput, imageOutput, total },
    costsUsd: costs,
    estimatedTotalUsd,
    warning
  };
}

export function solidUsageReport() {
  return {
    source: 'no-api-call',
    model: null,
    tokens: { input: 0, textInput: 0, imageInput: 0, imageOutput: 0, total: 0 },
    estimatedTotalUsd: 0,
    warning: []
  };
}

export function printUsageReport(report, log = console.log) {
  log('\n--- OpenAI image-edit token usage and cost ---');
  if (report.source === 'no-api-call') {
    log('Engine: solid-colour fill (no OpenAI API request)');
    log('Total tokens: 0');
    log('Estimated OpenAI API cost: $0.00000000 USD');
    log('------------------------------------------------\n');
    return;
  }
  const t = report.tokens;
  log('Model: ' + report.model);
  log('Input tokens: ' + shown(t.input));
  log('  Text input: ' + shown(t.textInput));
  log('  Image input: ' + shown(t.imageInput));
  log('Output image tokens: ' + shown(t.imageOutput));
  log('TOTAL TOKENS: ' + shown(t.total));

  if (report.costsUsd) {
    log('Text input cost:  ' + dollars(report.costsUsd.textInput));
    log('Image input cost: ' + dollars(report.costsUsd.imageInput));
    log('Image output cost:' + dollars(report.costsUsd.imageOutput));
  }
  log('ESTIMATED TOTAL COST: ' + dollars(report.estimatedTotalUsd) + ' USD');
  for (const message of report.warning) log('WARNING: ' + message);
  log('Pricing: OpenAI Standard API rates as of ' + report.pricingAsOf + '.');
  log('This is an estimate from API token usage, not an invoice; taxes and discounts are excluded.');
  log('------------------------------------------------\n');
}
