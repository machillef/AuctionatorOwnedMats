# Auctionator: Owned Mats

A companion addon for [Auctionator](https://www.curseforge.com/wow/addons/auctionator) on **WoW: Forever**.

Auctionator normally calculates crafting costs as if you have to buy every reagent from scratch. **Auctionator: Owned Mats** also counts what is already in your bags, so you can see how much you still need to spend, what the real profit of a craft is, and which recipes make the most gold from the materials you already own.

**Requires: Auctionator**

## Features

### Bag-aware cost and profit in the Professions window

Right below Auctionator's *To Craft* and *Profit* lines, the addon adds two more lines:

- **Price of missing mats**: the cost of only the reagents you do not already have in your bags. It turns green when you have everything on hand, and amber when you are still missing something.
- **Cash Profit**: your profit after the 5% Auction House cut, counting only the gold you still have to spend. Green when positive, red when negative.

### Best Crafts window

Click the **Best Crafts** button in the Professions window, or type `/aom list`, to get an overview of your current profession:

- Checks all of your learned recipes for the open profession against your bags and Auctionator prices.
- Filter the list with **Have Mats**, **Ready Only**, **All Recipes**, and **True Profit > 0 only**.
- Sort by **Recipe**, **Missing Mats**, **Cash Profit**, or **True Profit**.
- Tooltips show the reagent breakdown and how old each Auction House price is.
- Click a row to jump straight to that recipe in the Professions window.
- While the Auction House is open, click **Scan AH** to run a live Auctionator search for the listed recipes and reagents, updating profits as results come in.

### Not Learned tab

Before buying a new recipe, check the **Not Learned** tab to see what you have not learned yet for the open profession and decide whether it is worth picking up:

- **Recipe Cost**: the Auction House or vendor price of the recipe item.
- **Profit/Craft**: the profit from one craft if you buy all the materials.
- **Payback**: how many crafts it takes to earn back the price of the recipe.

## Slash commands

- `/aom list` (also `/aom scan`, `/aom best`): show or hide the Best Crafts window.
- `/aom toggle`, `/aom on`, `/aom off`: show or hide the extra lines in the Professions window.
- `/aom debug`: print a reagent-by-reagent cost and bag breakdown for the selected recipe.

## Notes

- Prices come from Auctionator, so scan the Auction House with Auctionator (or use **Scan AH**) to keep them up to date.
- Recipe items are matched by their English names, so the Not Learned tab works best on English clients.

## Feedback

If you run into a bug or have a feature request, let me know on [GitHub Issues](https://github.com/machillef/AuctionatorOwnedMats/issues).
