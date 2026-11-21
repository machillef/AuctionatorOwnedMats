# AuctionatorOwnedMats

A lightweight companion addon for **Auctionator** on **WoW: Forever (`1.60.1` / Interface `16001`)**.

## Features

- **Bag-adjusted crafting breakdown** directly below Auctionator's `To Craft` and `Profit` lines in the Professions window:
  - **Price of missing mats**: cost of only the reagents you do not already have in your bags (amber when missing mats remain, green when all mats are in your bags).
  - **Cash Profit**: net profit after the 5% AH cut based only on the missing reagents you still need to buy (green when positive, red when negative).
- **Best Crafts scanner** (`Best Crafts` button in the Professions header or `/aom list`):
  - Scans all learned recipes in the open profession against your bags and Auctionator prices.
  - Filters for `Have Mats`, `Ready Only`, `All Recipes`, and `True Profit > 0 only`.
  - Sortable columns (`Recipe`, `Missing Mats`, `Cash Profit`, `True Profit`) with detailed hover tooltips (including reagent breakdown and AH price age).
  - Click any row to select that recipe directly in the Professions window.
  - **`Not Learned`** tab: recipes of the open profession you have not learned yet, with `Recipe Cost` (AH or vendor price of the recipe item), `Profit/Craft` (all mats bought) and `Payback` (crafts needed to earn the recipe cost back). The recipe item is found by its English name (`Recipe:`, `Pattern:`, `Plans:` …) in AH results and remembered per character.
  - **`Scan AH`** button (when the Auction House is open) triggers a live `Auctionator.API.v1.MultiSearchExact` scan for the filtered recipes and reagents and updates profits in real time.

## Installation

1. Ensure **Auctionator** is installed and enabled.
2. Copy the `AuctionatorOwnedMats` folder into:
   ```text
   World of Warcraft\_forever_\Interface\AddOns\AuctionatorOwnedMats
   ```
3. Launch (or restart) WoW and enable **Auctionator: Owned Mats** in the AddOns list.

## Slash Commands

- `/aom list` (or `/aom scan`, `/aom best`) — Toggle the **Best Crafts** window.
- `/aom toggle` / `/aom on` / `/aom off` — Show or hide the inline recipe lines.
- `/aom debug` — Print a reagent-by-reagent cost and bag breakdown for the selected recipe.
