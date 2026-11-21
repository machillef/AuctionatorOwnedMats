# Auctionator: Owned Mats

**Auctionator: Owned Mats** is a companion addon for [Auctionator](https://www.curseforge.com/wow/addons/auctionator) on **WoW: Forever**. Auctionator tells you what a craft costs if you buy every reagent. This addon also counts the materials already in your bags. It shows what you still need to buy, the real profit of each craft, and which recipes make the most money from the materials you already own.

**Requires:** Auctionator.

## Features

### Bag-aware cost and profit in the Professions window

Two extra lines appear below Auctionator's *To Craft* and *Profit* lines:

- **Price of missing mats**: the cost of only the reagents you do not already have in your bags. It turns green when everything is in your bags and amber when something is still missing.
- **Cash Profit**: profit after the 5% Auction House cut, counting only the gold you still have to spend. It is green when positive and red when negative.

### Best Crafts window

Open it with the **Best Crafts** button in the Professions window, or type `/aom list`.

- Scans every learned recipe of the open profession against your bags and Auctionator prices.
- Filters: **Have Mats**, **Ready Only**, **All Recipes** and **True Profit > 0 only**.
- Sortable columns: Recipe, Missing Mats, Cash Profit and True Profit.
- Tooltips show the reagent breakdown and the age of each Auction House price.
- Click a row to open that recipe in the Professions window.
- **Scan AH** (while the Auction House is open) runs a live Auctionator search for the listed recipes and reagents and updates profits as the results arrive.

### Not Learned tab

Shows the recipes of the open profession that you have not learned yet, so you can decide whether a recipe is worth buying:

- **Recipe Cost**: the Auction House or vendor price of the recipe item.
- **Profit/Craft**: the profit of one craft when you buy all materials.
- **Payback**: how many crafts it takes to earn back the price of the recipe.

## Slash commands

- `/aom list` (also `/aom scan`, `/aom best`): show or hide the Best Crafts window.
- `/aom toggle`, `/aom on`, `/aom off`: show or hide the extra lines in the Professions window.
- `/aom debug`: print a reagent-by-reagent cost and bag breakdown for the selected recipe.

## Notes

- Prices come from Auctionator. Scan the Auction House with Auctionator (or use **Scan AH**) to keep them fresh.
- Recipe items are matched by their English names, so the Not Learned tab works best on English clients.

## Feedback

Report bugs and request features on [GitHub Issues](https://github.com/machillef/AuctionatorOwnedMats/issues).
