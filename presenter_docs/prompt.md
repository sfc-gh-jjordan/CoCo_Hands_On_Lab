# Coco Interactive Workshop

## Summary

The Coco Interactive workshop is a hands-on enablement session (2-4 hours) to work with customers to understand Cortex Code in depth, its multiple surfaces (Snowsight, CLI, Desktop, Mobile), and how to use it effectively in a series of day-to-day scenarios.   

## Content

- An interactive HTML presentation that provides a quick overview of what Coco is, how it fits into the other AI capabilities like Cortex Agents, Analyst and Semantic views, why Snowflake developed it, the different surfaces and the reasoning for them, examples of use cases that Coco is built to solve, and an explanation of Coco pricing.  Also how Coco can be integrated into other AI tools like Claude, VS Code or Cursor. Wrap why its best for Snowflake.   The presentation should use a step by step navigation plus have an ability to jump forward and back if the need arises to move to a different topic.   It should also include diagrams and graphics to make it interesting.  Also have the HTML support light and dark mode.   Also at the end include a final slide to reveal that this was built using Coco Desktop with a Coco pengun logo.  Wrap it with a page of links for Coco documentation and Snowflake Coco blogs and a "thank you" slide at the end.

- A collection of step by step labs that customers follow as hands on scenarios. Each should include a sharable workbook document, example prompts, and sample schemas, tables, data (if required).   The labs should cover each surface except mobile since its only in private preview currently.  Consider the best fit scenarios for that surface.   Topics should include data engineering, data quality, analytics, ai agents, notebooks/data science.   Also include focus areas on generating coco skills, diagramming (e.g ER Diagrams or data flow diagrams as HTML or Mermaid), Cost optimization, addressing performance concerns, checking warehouse and query health and other day to day admin efforts.

## Considerations/Instructions

- Design the content, especially the labs to be sharable so a customer can run these in their own account, or if required in a trial account.  Perhaps a public github would be the simplest approach.

- Make the HTML presentation flexible so I can customize it with the customer's name and logo before presenting and sharing with them.   

- Make sure to avoid language calling the customer "customer", and instead use their name where possible or just use the word "you".

- Make sure the presentation elements on diagrams can be highlighted to help me point out where I'm focusing their attention.

- Test each lab carefully and consider not making each too long in duration - no more than 15-30 minutes per lab.

- Use the demo skills when creating the assets for each lab so that each lab is self contained with its own database, schema, tables, data and other content and can also be torn down with no impact to a customers existing environment.

- The presentation should only take 15-20 minutes to cover and then leave the reamining time for labs.   

- For a 2 hours session ideally should be able to cover the presentation and 4-5 labs if possible.

- Suggest and recommend labs to add that would be compelling for a customer who's dabbled with Coco but not put it into active constant use.   I'd like to build up a repo of labs that I can eventually suggest to a prospective customer and they choose which ones they'd like to try.
