import test from 'node:test';
import assert from 'node:assert/strict';
import {MODEL_RATES,imageEditUsageReport,printUsageReport,solidUsageReport} from '../src/usage.mjs';

const example = {
  input_tokens: 1100,
  input_tokens_details: {text_tokens:100,image_tokens:1000},
  output_tokens: 2300,
  total_tokens: 3400
};

for(const model of ['gpt-image-2.5-sunburst','gpt-image-2.5-flare']) {
  test(model + ' prints token totals and accurate Standard pricing',()=>{
    const report=imageEditUsageReport(example,model);
    assert.deepEqual(report.tokens,{
      input:1100,textInput:100,imageInput:1000,imageOutput:2300,total:3400
    });
    assert.equal(report.costsUsd.textInput,0.0005);
    assert.equal(report.costsUsd.imageInput,0.008);
    assert.equal(report.costsUsd.imageOutput,0.069);
    assert.ok(Math.abs(report.estimatedTotalUsd-0.0775)<1e-12);
    const lines=[];
    printUsageReport(report,line=>lines.push(line));
    const terminal=lines.join('\n');
    assert.match(terminal,/TOTAL TOKENS: 3,400/);
    assert.match(terminal,/ESTIMATED TOTAL COST: \$0\.07750000 USD/);
    assert.match(terminal,/Text input: 100/);
    assert.match(terminal,/Image input: 1,000/);
  });
}

test('Missing API usage is unknown, not zero or a fabricated cost',()=>{
  const report=imageEditUsageReport(undefined,'gpt-image-2.5-sunburst');
  assert.equal(report.tokens.total,null);
  assert.equal(report.estimatedTotalUsd,null);
  const lines=[];printUsageReport(report,line=>lines.push(line));
  assert.match(lines.join('\n'),/TOTAL TOKENS: unavailable/);
  assert.match(lines.join('\n'),/ESTIMATED TOTAL COST: unavailable/);
  assert.match(lines.join('\n'),/WARNING/);
});

test('Missing modality breakdown does not invent a cost',()=>{
  const report=imageEditUsageReport({input_tokens:1100,output_tokens:2300,total_tokens:3400},
    'gpt-image-2.5-flare');
  assert.equal(report.tokens.total,3400);
  assert.equal(report.estimatedTotalUsd,null);
  assert.ok(report.warning.length);
});

test('Inconsistent token counts do not produce cost',()=>{
  const report=imageEditUsageReport({...example,total_tokens:3401},'gpt-image-2.5-sunburst');
  assert.equal(report.estimatedTotalUsd,null);
  assert.ok(report.warning.some(x=>x.includes('subtotals')));
});

test('Missing total is derived from supplied input and output counts',()=>{
  const {total_tokens,...usage}=example;
  const report=imageEditUsageReport(usage,'gpt-image-2.5-sunburst');
  assert.equal(report.tokens.total,3400);
  assert.ok(Math.abs(report.estimatedTotalUsd-0.0775)<1e-12);
});

test('No OpenAI call reports exactly zero tokens and cost',()=>{
  const report=solidUsageReport();
  assert.equal(report.tokens.total,0);
  assert.equal(report.estimatedTotalUsd,0);
  const lines=[];printUsageReport(report,line=>lines.push(line));
  assert.match(lines.join('\n'),/Total tokens: 0/);
  assert.match(lines.join('\n'),/cost: \$0\.00000000 USD/);
});

test('Both supported models have verified matching per-million rates',()=>{
  assert.deepEqual(MODEL_RATES['gpt-image-2.5-sunburst'],{
    textInput:5,imageInput:8,imageOutput:30
  });
  assert.deepEqual(MODEL_RATES['gpt-image-2.5-flare'],MODEL_RATES['gpt-image-2.5-sunburst']);
});
