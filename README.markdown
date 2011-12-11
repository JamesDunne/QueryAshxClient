
# query.ashx

## What is it?

`query.ashx` is a web-based SQL query tool deployed as a single ashx file into any ASP.NET host, existing or new.

## Author

James S. Dunne, bittwiddlers.org

## Features

 - Extremely simple deployment
 - Simple jQuery-based web user interface
 - Safe, SELECT-only SQL queries executed against any database that the IIS application pool has access to (or the credentials supplied in the connection string if not SSPI auth)
 - Recorded log of all queries submitted
 - Parameterized query support
 - Custom database connection strings
 - HTML table showing query results
 - Several varieties of tool-friendly output modes in JSON or XML containers
 - Secured data mutation feature for submitting SQL queries to INSERT, UPDATE, DELETE data
 - - Secured access via RSA public key authorization
 - - Public key management: authorize/revoke public keys for access
 - - This functionality is only accessible via WindowsClient project due to security constraints
 - Windows Forms client application for better user experience
 - Online self-update feature (downloads latest query.ashx code from github)
