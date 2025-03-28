### ALERT: please read before reviewing:
https://docs.google.com/document/d/1p1Gep8hjgPD5kodpUgw8Fpq1g7-fvPWuYDOLBJAwSSU/edit?usp=sharing

## Summary

## Issue ticket link
https://technologyprogramme.atlassian.net/browse/GCSA-

## Checklist before requesting a review
- [] I have added tests to new code and updated existing tests where needed
- [] I have added docs for public functions, classes, etc.
- [] I have followed https://peps.python.org/pep-0008/#designing-for-inheritance (e.g `_` leading underscore for non-public functions)
- [] I have defined function parameters and type hints and not abused kwargs usage.
- [] I have added logging statements where necessary.
- [] I have encapsulated features into functions and classes not defined python scripts at module level (avoid  https://docs.python.org/3/tutorial/modules.html#executing-modules-as-scripts)
- [] I have avoided side effects in module imports (```e.g. db_connection = connect_to_database() in database.py module file ``)
- [] I have favored dependency injection over module side-effects.

## Relevant files

## Screenshots


## IMPORTANT: Please read before reviewing
Due to the way the Copilot project is set up with different instances for development, testing and production, configuration changes or API bugs within the API framework itself will be made directly to the `dev-production` branch and able to be applied across the other PRs that are merging into it.

However, these changes are not always pulled in directly, and must sometimes be manually approved to 'upgrade' the PR to be in line with the particular branch it is being merged into. This can be done by clicking the 'Update Branch' button at the bottom of each PR page (see image below):

![Screenshot 2024-04-03 at 09 42 10](https://github.com/Government-Communication-Service/copilot-api/assets/157805109/e6a7237b-377f-4acf-813a-c5425c7c419c)

Please ensure during reviews that the current PR you are testing is up-to-date with the overall branch, and if not that you manually sync these changes by pressing the update branch button.
