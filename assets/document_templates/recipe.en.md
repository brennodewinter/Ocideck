<!-- form id=recept version=1 lang=en controller="Example editorial team" contact="editors@example.org" retain-unused="6 months after closing" overview="naam,gerecht" -->
# Recipe submission (example)

This is an example form for trying out OciDeck. Fill it in, add a photo and save the submission as a zip.

<!-- notice -->
Your details are used only for this example. The editors keep them until 6 months after closing; submissions that do not make it into the book are deleted after that.
<!-- /notice -->

## A. About you

<!-- field id=naam type=text required max-chars=60 -->
**Name**
<!-- answer -->
<!-- /field id=naam -->

<!-- field id=mail type=text required pattern=email -->
**Email address**
<!-- answer -->
<!-- /field id=mail -->

<!-- field id=bio type=prose words=..80 -->
**Short bio**
> A few sentences about yourself. May be left empty.
<!-- answer -->
<!-- /field id=bio -->

## B. The dish

<!-- field id=gerecht type=text required -->
**Name of the dish**
<!-- answer -->
<!-- /field id=gerecht -->

<!-- field id=moeilijkheid type=choice options="Easy|Medium|Advanced" required -->
**How difficult is it?**
<!-- answer -->
<!-- /field id=moeilijkheid -->

<!-- field id=dieet type=multichoice options="Vegetarian|Vegan|Halal|Gluten-free" other -->
**Which diet is it suitable for?**
<!-- answer -->
<!-- /field id=dieet -->

<!-- field id=ingredienten type=table columns="Ingredient|Amount" rows=1.. required -->
**Ingredients**
<!-- answer -->
<!-- /field id=ingredienten -->

<!-- field id=bereiding type=list ordered items=2..20 required -->
**Method**
> One step per item.
<!-- answer -->
<!-- /field id=bereiding -->

## C. The story and the photo

<!-- field id=verhaal type=prose required words=50..150 -->
**The story behind the dish**
> Who taught you? When do you make it? Why does it matter to you?
<!-- answer -->
<!-- /field id=verhaal -->

<!-- field id=datum type=date -->
**When did you first make it?**
<!-- answer -->
<!-- /field id=datum -->

<!-- field id=foto type=image count=0..3 min-width=1200 alt credit -->
**Photos of the dish**
> Preferably a photo you took yourself. Location data is removed.
<!-- answer -->
<!-- /field id=foto -->

## D. Consent

<!-- field id=akkoord type=consent required -->
I agree that my recipe, story and photos are published.
<!-- answer -->
- [ ]
<!-- /field id=akkoord -->

Thank you for your submission!
