# Padding batch review — 15 October 2026

Source: local `output/batch-padding/summary.json` generated from the first 108-image preview run.

## Reported result

- 47 audited Products CMS items / 108 linked Images CMS items.
- **101 ready**, including 45 hero images and 56 other gallery images.
- **6 skipped**, including 2 hero images and 4 other gallery images.
- **1 failed** gallery image (OpenAI HTTP 520).
- 0 applied, 0 rolled back: preview run only.
- 101 recorded successful OpenAI image-edit calls; 327,947 tokens; **$6.357041 USD** recorded estimated cost.
- 1 started API call has no usage receipt and might have been billed separately. **Overall total is incomplete.**

## Unresolved image IDs

| Product | Image item ID | Role | Reported issue |
| --- | --- | --- | --- |
| Allegra 750ml Bottle (White) | `6ac695326e49045ca5ee8dec` | Gallery | Unsafe interior detection |
| Arc Eco Square Wireless Charger | `6ac68d0b1552026a605e13d3` | Hero | Unsafe interior detection |
| Casual Braided Belt (Navy Brown) | `6ac68f89d92cda95eb51ac8d` | Hero | Unsafe interior detection |
| Casual Braided Belt (Black Black) | `6ac68f881c342211e8d597b9` | Gallery | Unsafe interior detection |
| Oakleigh Coffee Cup (354mL) (White) | `6ac6948b14526571351528ef` | Gallery | OpenAI HTTP 520 (no saved usage receipt) |
| Summit 750ml Drink Bottle (White) | `6ac69536f4670283e5ab6e84` | Gallery | Unsafe interior detection |
| Sunrise Smoothie 500mL Tumbler (White) | `6ac6952900df4c45cf93d351` | Gallery | Unsafe interior detection |

The six skipped images were rejected by the conservative rectangle detector, not by OpenAI. **Do not** loosen or bypass padding detection globally without inspecting each original. They may be white-on-white images with indistinct photographic borders, images that already fill the canvas, or other cases.

The Oakleigh HTTP 520 was returned from `api.openai.com`. An API request may have been billed without an image/usage receipt. Automatic repurchase is deliberately disabled; require an explicitly reviewed retry for this exact image only if needed.

## Required before applying

1. Run `npm run batch:review` in `tools/image-padding`. This generates original-vs-preview contact sheets for the 101 ready records and a separate `review-sheets/needs-attention-01.webp` for the seven unresolved records; **no network calls and no CMS changes**.
2. Review every generated image for product fidelity, retained shadows, seams, unnatural backgrounds, clipping, aspect ratio, and image integrity. "Ready" means processed, not visually approved.
3. Determine whether each of six skipped images actually needs a fix. If yes, develop a targeted strategy for those images only and keep the 101 existing previews intact.
4. Decide explicitly whether to retry the single failed Oakleigh image, acknowledging a possible additional charge.
5. Only then run the **separate, explicitly confirmed** staged apply; avoid site publishing until post-upload QA.

## Fix already committed

The recorded usage aggregation originally set `usage.completeCost=true` despite `uncertainCalls=1`. Batch summary generation now reports **incomplete/partial cost** when any API request lacks a usage receipt. To update the existing local `summary.json` without regenerating images: `npm run batch:summary`.

No CMS records were modified for this review.
