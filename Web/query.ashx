<%@ WebHandler Language="C#" Class="AdHocQuery.AdHocQueryServiceProvider" %>
<%@ Assembly Name="System.Core, Version=3.5.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089" %>
<%@ Assembly Name="System.Data, Version=2.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089" %>
<%@ Assembly Name="System.Runtime.Serialization, Version=3.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089" %>
<%@ Assembly Name="System.Xml, Version=2.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089" %>

// SQL Query Builder/Executor web tool
// Designed and implemented by James S. Dunne (github.com/JamesDunne)
// on 2011-10-13

// This file was sourced from gist.github.com/1286172

// TODO: add optional TOP(N) clause
// TODO: AJAX requests for all data

// This changes depending on if attached to a debugger, apparently.
#define DEBUG
//#undef DEBUG

// Enable when disconnected and/or cannot access 'ajax.googleapis.com'
//#define Local

// Enable logging of queries to ~/query.ashx.log
#define LogQueries

// Enable tip-jar and credits
//#define TipJar
#define Credits

using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Web;
using System.Xml.Serialization;

namespace AdHocQuery
{
    public class AdHocQueryServiceProvider : IHttpHandler
    {
        /// <summary>
        /// Default connection string's name from your web.config &lt;connectionStrings&gt; section.
        /// </summary>
        const string DefaultConnectionStringName = "FIXME";

        /// <summary>
        /// URL of the latest version to use for self-update feature.
        /// </summary>
        const string LatestVersionURL = "https://raw.github.com/JamesDunne/QueryAshxClient/master/Web/query.ashx";

        /// <summary>
        /// SET ROWCOUNT limit for queries.
        /// </summary>
        const int defaultRowLimit = 1000;

        /// <summary>
        /// The master authorized public keys for the commit feature. These must be OpenSSL formatted RSA public keys encoded in BASE-64.
        /// </summary>
        private static readonly string[] defaultAuthorizedPublicKeys = new string[] {
            // Same public key except different keytype ("ssh-rsa" vs. "rsa"):
            @"AAAAA3JzYQAAAAEjAAAAgK7Nu+KxnCCe+VVIQvCIXe1jqT9YcfYek1Y42HAAJiVuiTLV9Ng4cR8vc5bI2aui1aAkMrajYoP/vfLM8Fu82n1P8ufvmuQ3BoJbuWtfJUcz9216Z+TvOjZq4dtX9AZB6dYa8vnwqcaiDbkaXE06ODjwqfWgqqc+KWaHLpYNosEv",
            @"AAAAB3NzaC1yc2EAAAABIwAAAICuzbvisZwgnvlVSELwiF3tY6k/WHH2HpNWONhwACYlboky1fTYOHEfL3OWyNmrotWgJDK2o2KD/73yzPBbvNp9T/Ln75rkNwaCW7lrXyVHM/dtemfk7zo2auHbV/QGQenWGvL58KnGog25GlxNOjg48Kn1oKqnPilmhy6WDaLBLw==",
        };

        private int rowLimit = defaultRowLimit;

        private HttpContext ctx;
        private HttpRequest req;
        private HttpResponse rsp;

        public void ProcessRequest(HttpContext ctx)
        {
            this.ctx = ctx;
            req = ctx.Request;
            rsp = ctx.Response;

            // Special tool modes:
            if (getFormOrQueryValue("self-update") != null)
            {
                selfUpdate();
                return;
            }
            else if (getFormOrQueryValue("mu") == "0")
            {
                modifyCommit(false);
                return;
            }
            else if (getFormOrQueryValue("mu") == "1")
            {
                modifyCommit(true);
                return;
            }
            else if (getFormOrQueryValue("ap") != null)
            {
                addPublicKey();
                return;
            }
            else if (getFormOrQueryValue("rp") != null)
            {
                revokePublicKey();
                return;
            }

            try
            {
                bool noHeader = false;
                bool noQuery = false;
                if (getFormOrQueryValue("no_header") != null) noHeader = true;
                if (getFormOrQueryValue("no_query") != null) noQuery = true;

                string rowlimitStr = getFormOrQueryValue("rowlimit");
                if ((rowlimitStr != null) && !Int32.TryParse(rowlimitStr, out rowLimit))
                {
                    // If parsing failed, reset the rowLimit to the default:
                    rowLimit = defaultRowLimit;
                }

                if (String.Equals(getFormOrQueryValue("output"), "json", StringComparison.OrdinalIgnoreCase))
                {
                    // JSON with each row a dictionary object { "column_name1": "value1", ... }
                    // Each column name must be unique or the JSON will be invalid.
                    renderJSON(JsonOutput.Dictionary, noQuery, noHeader);
                }
                else if (String.Equals(getFormOrQueryValue("output"), "json2", StringComparison.OrdinalIgnoreCase))
                {
                    // JSON with each row an array of objects [ { "name": "column_name1", "value": "value1" }, ... ]
                    // Each column name does not have to be unique, but produces objects that are more of a hassle to deal with.
                    renderJSON(JsonOutput.KeyValuePair, noQuery, noHeader);
                }
                else if (String.Equals(getFormOrQueryValue("output"), "json3", StringComparison.OrdinalIgnoreCase))
                {
                    // JSON with each row an array of values [ value1, value2, value3, ... ]
                    renderJSON(JsonOutput.Array, noQuery, noHeader);
                }
                else if (String.Equals(getFormOrQueryValue("output"), "xml", StringComparison.OrdinalIgnoreCase))
                {
                    // XML with <column name="column_name">value</column>
                    renderXML(XmlOutput.FixedColumns, noQuery, noHeader);
                }
                else if (String.Equals(getFormOrQueryValue("output"), "xml2", StringComparison.OrdinalIgnoreCase))
                {
                    // XML with <column_name>value</column_name>; column_name is scrubbed for XML compliance and produces hard-to-predict element names.
                    renderXML(XmlOutput.NamedColumns, noQuery, noHeader);
                }
                else
                {
                    renderHTMLUI();
                }
            }
            catch (Exception ex)
            {
                rsp.Clear();
                rsp.StatusCode = 500;
                rsp.ContentType = "text/html";
                rsp.Write(ex.ToString());
                return;
            }
        }

        private void selfUpdate()
        {
            string updateAppRelPath = req.AppRelativeCurrentExecutionFilePath;
            string updateAbsPath = ctx.Server.MapPath(updateAppRelPath);

            string newVersion = null;

            // Download the latest version from github:
            try
            {
                var wreq = System.Net.HttpWebRequest.Create(LatestVersionURL);
                using (var wrsp = wreq.GetResponse())
                using (var wrspstr = wrsp.GetResponseStream())
                using (var tr = new System.IO.StreamReader(wrspstr, Encoding.UTF8))
                    newVersion = tr.ReadToEnd();
            }
            catch (Exception ex)
            {
                // Failed retrieving.
                rsp.StatusCode = 500;
                rsp.Output.Write("Failed retrieving latest version from github: {0}", ex.Message);
                return;
            }

            // Update the current executing ashx file with the new contents:

            try
            {
                // TODO: skip overwriting clearly marked user-defined sections
                System.IO.File.WriteAllText(updateAbsPath, newVersion, Encoding.UTF8);
            }
            catch (Exception ex)
            {
                // Failed writing.
                rsp.StatusCode = 500;
                rsp.Output.Write("Failed writing latest version to '{0}': {1}", updateAppRelPath, ex.Message);
                return;
            }

            newVersion = null;

            // Redirect to the tool:
            UriBuilder rd = new UriBuilder(req.Url);
            rd.Query = "msg=Update+successful.";
            rsp.Redirect(rd.Uri.ToString());
            return;
        }

        private readonly string[] sqlTypes = new string[] { "int", "bit", "varchar", "nvarchar", "char", "nchar", "datetime", "datetime2", "datetimeoffset", "decimal", "money" };

        private void renderHTMLUI()
        {
            rsp.StatusCode = 200;
            rsp.ContentType = "text/html";

            System.IO.TextWriter tw = rsp.Output;

            // Head:
            tw.Write("<!doctype html><html><head><meta http-equiv=\"content-type\" content=\"text/html; charset=UTF-8\"><title>SQL Query Builder</title>");
            tw.Write(@"<style type=""text/css"">
body
{
    margin-top: 4px;
    margin-bottom: 4px;
    font-size: 12px;
}

a
{
    color: inherit;
    text-decoration: underline;
}

#footer,#header
{
    /*background-color: #daf4ff;*/
}

#header
{
    padding-bottom: 1em;
}

h3
{
    margin-top: 0.5em;
    margin-bottom: 0.25em;
    font-family: Tahoma, Arial;
    font-weight: bold;
    font-size: small;
}

p, li
{
    font-family: Tahoma, Arial;
    font-weight: normal;
    font-size: small;
    margin-top: 0.25em;
    margin-bottom: 0em;
}

.exception
{
    font-weight: bold;
    font-size: small;
}

pre, textarea, .monospaced, td.hexvalue
{
    font-family: Anonymous Pro, Anonymous, Consolas, Courier New, Courier;
}

.sqlkeyword
{
    font-weight: bold;
}

#query>pre
{
    font-size: small;
    margin-left: 1em;
    overflow-x: auto;
}

td>nobr>pre
{
    margin: 0
}

td>pre
{
    margin: 0
}

.input-table
{
    font-family: Tahoma, Segoe UI, Arial;
    font-size: small;
    padding-bottom: 1em;
}

.input-table>caption
{
    font-family: Tahoma, Segoe UI, Arial;
    font-size: medium;
    font-weight: bold;
}

.input-table>caption,.input-table>thead,.input-table>tfoot
{
    background-color: #3ef;
}

.input-table>tbody>tr:nth-child(even)
{
    background-color: #eef;
}

div#resultsView
{
    display: block;
    margin-top: 0.5em;
}

div#resultsInner
{
    margin-left: 1em;
}

div#resultsTableDiv
{
    clear: both;
    max-width: 1280;
    max-height: 30em;
    overflow-x: auto;
    overflow-y: auto;
}

#resultsTable
{
    font-family: Tahoma, Segoe UI, Arial;
    font-size: small;
    border-style: solid;
    border-width: thin;
}

#resultsTable>colgroup:nth-child(even)
{
    background-color: #f3f3aa;
}

#resultsTable>thead
{
    background-color: #bee;
    padding-bottom: 0.5em;
}

#resultsTable>tbody>tr:nth-child(even)
{
    background-color: #eef;
}

td.rn
{
    text-align: right;
    background-color: #880;
}

td.nullvalue
{
    font-weight: bold;
    background-color: #AA6;
}

th
{
    background-color: #fda;
    text-align: left;
}

th.coltype
{
    background-color: #fec;
}

#footer
{
    padding-top: 2em;
    font-family: Tahoma, Arial;
    font-weight: normal;
    font-size: small;
}
</style>");

            string csname, cs, withCTEidentifier, withCTEexpression, select, from, where, groupBy, having, orderBy;

            // Pull FORM values:
            csname = getFormOrQueryValue("csname");
            cs = getFormOrQueryValue("cs");
            withCTEidentifier = getFormOrQueryValue("wi");
            withCTEexpression = getFormOrQueryValue("we");
            select = getFormOrQueryValue("select");
            from = getFormOrQueryValue("from");
            where = getFormOrQueryValue("where");
            groupBy = getFormOrQueryValue("groupBy");
            having = getFormOrQueryValue("having");
            orderBy = getFormOrQueryValue("orderBy");

            bool actionExecute = String.Equals(getFormOrQueryValue("action"), "Execute", StringComparison.OrdinalIgnoreCase);
            bool actionLog = String.Equals(getFormOrQueryValue("action"), "Log", StringComparison.OrdinalIgnoreCase);

            // Validate and convert parameters:
            ParameterValue[] parameters;
            bool parametersValid = convertParameters(out parameters);

            // Dynamically show/hide the rows depending on which FORM values we have provided:
            tw.Write("<style type=\"text/css\">");
            string message = getFormOrQueryValue("msg");

            bool displayWITH = !String.IsNullOrEmpty(withCTEidentifier) && !String.IsNullOrEmpty(withCTEexpression);
            bool displayFROM = !String.IsNullOrEmpty(from);
            bool displayWHERE = !String.IsNullOrEmpty(where);
            bool displayGROUPBY = !String.IsNullOrEmpty(groupBy);
            bool displayHAVING = !String.IsNullOrEmpty(having);
            bool displayORDERBY = !String.IsNullOrEmpty(orderBy);
            tw.WriteLine("tr#rowWITH    {{ {0} }}", displayWITH ? String.Empty : "display: none;");
            tw.WriteLine("tr#rowFROM    {{ {0} }}", displayFROM ? String.Empty : "display: none;");
            tw.WriteLine("tr#rowWHERE   {{ {0} }}", displayWHERE ? String.Empty : "display: none;");
            tw.WriteLine("tr#rowGROUPBY {{ {0} }}", displayGROUPBY ? String.Empty : "display: none;");
            tw.WriteLine("tr#rowHAVING  {{ {0} }}", displayHAVING ? String.Empty : "display: none;");
            tw.WriteLine("tr#rowORDERBY {{ {0} }}", displayORDERBY ? String.Empty : "display: none;");

            tw.WriteLine("</style>");

#if Local
            // Import jQuery 1.6.2:
            tw.WriteLine(@"<script type=""text/javascript"" src=""jquery.min.js""></script>");
            // Import jQueryUI 1.8.5:
            tw.WriteLine(@"<script type=""text/javascript"" src=""jquery-ui.min.js""></script>");
            tw.WriteLine(@"<link rel=""stylesheet"" type=""text/css"" href=""jquery-ui.css"" />");
#else
            // Import jQuery 1.6.2:
            tw.WriteLine(@"<script type=""text/javascript"" src=""http://ajax.googleapis.com/ajax/libs/jquery/1.6.2/jquery.min.js""></script>");
            // Import jQueryUI 1.8.5:
            tw.WriteLine(@"<script type=""text/javascript"" src=""http://ajax.googleapis.com/ajax/libs/jqueryui/1.8.5/jquery-ui.min.js""></script>");
            tw.WriteLine(@"<link rel=""stylesheet"" type=""text/css"" href=""http://ajax.googleapis.com/ajax/libs/jqueryui/1.8.5/themes/redmond/jquery-ui.css"" />");
#endif

            string sqlTypesOptionList = javascriptStringEncode(generateOptionList(sqlTypes));

            // Default tab is 'Query':
            int selectedTabIndex = 0;
            if (actionExecute && parametersValid) selectedTabIndex = 2;
            else if (actionLog) selectedTabIndex = 2;
            else if (message != null) selectedTabIndex = 3;

            // Now write out the javascript to allow toggling of show/hide per each query builder row:
            tw.WriteLine(@"<script type=""text/javascript""><!--
$(function() {
    $('#btnWITH')   .click(function() { $('#rowWITH').toggle(); return false; });
    $('#btnFROM')   .click(function() { $('#rowFROM').toggle(); return false; });
    $('#btnWHERE')  .click(function() { $('#rowWHERE').toggle(); return false; });
    $('#btnGROUPBY').click(function() { $('#rowGROUPBY').toggle(); return false; });
    $('#btnHAVING') .click(function() { $('#rowHAVING').toggle(); return false; });
    $('#btnORDERBY').click(function() { $('#rowORDERBY').toggle(); return false; });

    // Enable the tabbed view:
    $('#tabs').tabs();
    $('#tabs').tabs('select', " + selectedTabIndex.ToString() + @");

    // Enable buttons:
    $('input:submit, a.button, button').button();

    // Parameters:
    var removeHandler = function() {
        $(this).parent().parent().remove();
        return false;
    }
    $('.btnRemove').click(removeHandler);

    $('#btnAddParameter').click(function() {
        $('#parametersBody').append('<tr><td><button class=\'btnRemove\'>-</button></td><td><input type=\'text\' name=\'pn\' /></td><td><select name=\'pt\'>" + sqlTypesOptionList + @"</select></td><td><input type=\'text\' name=\'pv\' size=\'60\' /></td></tr>');
        $('.btnRemove').button().unbind('click').bind('click', removeHandler);
        return false;
    });

    var coltypeVisible = false;
    $('#toggleColumnTypeHeaders').click(function() {
        // Toggle the visibility of the coltype header cells:
        if (coltypeVisible)
        {
            $('th.coltype').hide().prev().attr('colspan', 2);
            $(this).button('option', 'label', 'Show Types');
            coltypeVisible = false;
        }
        else
        {
            $('th.coltype').show().prev().removeAttr('colspan');
            $(this).button('option', 'label', 'Hide Types');
            coltypeVisible = true;
        }
        return false;
    });
});
//-->
</script>");

            // Start the <body> section:
            tw.Write("</head><body bgcolor='#ffffff' text='#222222' link='#1122cc' vlink='#6611cc' alink='#d14836'>");

            // Create the main form wrapper:
            tw.Write("<div><form method=\"post\" action=\"{0}\">", HttpUtility.HtmlAttributeEncode(req.Url.AbsolutePath));


            // Tabs container:
            tw.Write("<div id='tabs'>\n");
            tw.Write("<ul>");
            tw.Write("<li><a href='#tab-builder'>Query</a></li>");
            tw.Write("<li><a href='#tab-connections'>Connection</a></li>");
            if (actionExecute && parametersValid) tw.Write("<li><a href='#tab-results'>Results</a></li>");
            tw.Write("<li><a href='#tab-log'>Query Log</a></li>");
            tw.Write("<li><a href='#tab-self-update'>Update</a></li>");
            tw.Write("</ul>\n");


            // Query-builder tab:
            {
                tw.Write("<div id='tab-builder'>");

                tw.Write("<table class='input-table' border='0' cellspacing='0' cellpadding='2'><tbody>");
                tw.Write("<tr><td>&nbsp;</td><td>");
                tw.Write("<button id='btnWITH'    >WITH</button>");
                tw.Write("<button id='btnSELECT' disabled='disabled' >SELECT</button>");
                tw.Write("<button id='btnFROM'    >FROM</button>");
                tw.Write("<button id='btnWHERE'   >WHERE</button>");
                tw.Write("<button id='btnGROUPBY' >GROUP BY</button>");
                tw.Write("<button id='btnHAVING'  >HAVING</button>");
                tw.Write("<button id='btnORDERBY' >ORDER BY</button>");
                tw.Write("</td></tr>");
                tw.Write("<tr id='rowWITH'><td class='monospaced sqlkeyword'>WITH</td><td style='vertical-align: middle'><input type='text' name='wi' size='12' value='{0}'/> <span class='monospaced sqlkeyword'>AS</span> (<textarea name='we' cols='78' rows='{2}' style='vertical-align: middle;'>{1}</textarea>)</td></tr>",
                    HttpUtility.HtmlAttributeEncode(withCTEidentifier ?? ""),
                    HttpUtility.HtmlEncode(withCTEexpression),
                    (withCTEexpression ?? "").Count(ch => ch == '\n') + 2
                );
                tw.Write("<tr><td class='monospaced sqlkeyword'>SELECT</td><td><textarea name='select' cols='100' rows='{1}'>{0}</textarea></td></tr>", HttpUtility.HtmlEncode(select ?? ""), (select ?? "").Count(ch => ch == '\n') + 2);
                tw.Write("<tr id='rowFROM'><td class='monospaced sqlkeyword'>FROM</td><td><textarea name='from' cols='100' rows='{1}'>{0}</textarea></td></tr>", HttpUtility.HtmlEncode(from ?? ""), (from ?? "").Count(ch => ch == '\n') + 2);
                tw.Write("<tr id='rowWHERE'><td class='monospaced sqlkeyword'>WHERE</td><td><textarea name='where' cols='100' rows='{1}'>{0}</textarea></td></tr>", HttpUtility.HtmlEncode(where ?? ""), (where ?? "").Count(ch => ch == '\n') + 2);
                tw.Write("<tr id='rowGROUPBY'><td class='monospaced sqlkeyword'>GROUP BY</td><td><textarea name='groupBy' cols='100' rows='{1}'>{0}</textarea></td></tr>", HttpUtility.HtmlEncode(groupBy ?? ""), (groupBy ?? "").Count(ch => ch == '\n') + 1);
                tw.Write("<tr id='rowHAVING'><td class='monospaced sqlkeyword'>HAVING</td><td><textarea name='having' cols='100' rows='{1}'>{0}</textarea></td></tr>", HttpUtility.HtmlEncode(having ?? ""), (having ?? "").Count(ch => ch == '\n') + 1);
                tw.Write("<tr id='rowORDERBY'><td class='monospaced sqlkeyword'>ORDER BY</td><td><textarea name='orderBy' cols='100' rows='{1}'>{0}</textarea></td></tr>", HttpUtility.HtmlEncode(orderBy ?? ""), (orderBy ?? "").Count(ch => ch == '\n') + 1);
                tw.Write("</tbody></table>");

                // Parameters:
                tw.Write("<table class='input-table' border='0' cellspacing='0' cellpadding='2'>");
                tw.Write("<caption>Parameters</caption>");
                tw.Write("<thead><tr><th style='width: 1em;'>&nbsp;</th><th style='width: 10em;'>Name</th><th style='width: 10em;'>Type</th><th style='width: 30em;'>Value</th></tr></thead>");
                tw.Write("<tbody id='parametersBody'>");

                for (int i = 0; i < parameters.Length; ++i)
                {
                    tw.Write("<tr><td><button class='btnRemove'>-</button></td><td><input type='text' name='pn' value='{0}'></input></td><td><select name='pt'>{1}</select></td><td><input type='text' name='pv' size='60' value='{2}'></input>{3}</td></tr>",
                        HttpUtility.HtmlAttributeEncode(parameters[i].Name),
                        generateOptionList(sqlTypes, parameters[i].RawType),
                        HttpUtility.HtmlAttributeEncode(parameters[i].RawValue),
                        parameters[i].IsValid ? String.Empty : String.Format("<br/><span class='error'>{0}</span>", HttpUtility.HtmlEncode(parameters[i].ValidationMessage))
                    );
                }

                tw.Write("</tbody>");
                tw.Write("<tfoot>");
                tw.Write("<tr><td>&nbsp;</td><td colspan='3'><span style='float: right;'><button id='btnAddParameter'>Add</button></span></td></tr>");
                tw.Write("</tfoot>");
                tw.Write("</table>");

                // Execute button:
                tw.Write("<input type='submit' name='action' value='Execute' />");

                tw.Write("</div>\n"); // id='tab-builder'
            }


            // Connection Manager:
            {
                tw.Write("<div id='tab-connections'><table class='input-table' border='0' cellspacing='0' cellpadding='2'><tbody>");
#if true
                // Drop-down for named connection strings:
                tw.Write("<tr><td>Named connection string:</td><td><select name='csname'>");
                tw.Write("<option value=''{0}>-- Use custom connection string --</option>", String.Equals(csname ?? "", "", StringComparison.OrdinalIgnoreCase) ? " selected='selected'" : String.Empty);
                foreach (System.Configuration.ConnectionStringSettings css in System.Configuration.ConfigurationManager.ConnectionStrings)
                {
                    tw.Write("<option value='{0}'{3}>[{1}] -- {2}</option>",
                        HttpUtility.HtmlAttributeEncode(css.Name),
                        HttpUtility.HtmlEncode(css.Name),
                        HttpUtility.HtmlEncode(css.ConnectionString),
                        String.Equals(csname, css.Name, StringComparison.OrdinalIgnoreCase) ? " selected='selected'" : String.Empty
                    );
                }
                tw.Write("</select></td></tr>");
#else
            tw.Write("<tr><td>Named connection string:</td><td><input type='text' name='csname' size='40' value='{0}' /></td></tr>", HttpUtility.HtmlAttributeEncode(csname ?? ""));
#endif
                tw.Write("<tr><td>Custom connection string:</td><td><input type='text' name='cs' size='110' value='{0}' /></td></tr>", HttpUtility.HtmlAttributeEncode(cs ?? ""));
                tw.Write("</tbody></table></div>\n");
            }


            // Execution:
            if (actionExecute && parametersValid)
            {
                string query;
                string[,] header;
                IEnumerable<IEnumerable<object>> rows;
                long execTimeMsec;

                // Execute the query:
                string errMessage;
                try
                {
                    errMessage = QuerySQL(csname, cs, withCTEidentifier, withCTEexpression, select, from, where, groupBy, having, orderBy, parameters, out query, out header, out execTimeMsec, out rows);
                }
                catch (Exception ex)
                {
                    errMessage = ex.Message;
                    query = null;
                    execTimeMsec = 0;
                    rows = null;
                    header = null;
                }

                tw.Write("<div id='tab-results'>");
                if (query != null)
                {
                    tw.Write("<div id='query'><h3>Query</h3><pre>{0}</pre></div>", HttpUtility.HtmlEncode(query));
                }

                if (errMessage != null)
                {
                    tw.Write("<div id='resultsView'><h3>Error</h3><div id='resultsInner'><span class='exception'>{0}</span></div></div>", HttpUtility.HtmlEncode(errMessage));
                    goto end;
                }

                // Output table:
                tw.Write("<div id='resultsView'>");
                tw.Write("<h3>Results</h3>");
                tw.Write("<div id='resultsInner'>");

                // Log the full absolute URL with host and path:
                string execURL = createURL().PathAndQuery;
                logQuery(query, execURL);

                string jsonURL = createURL("output", "json").PathAndQuery;
                string json2URL = createURL("output", "json2").PathAndQuery;
                string json3URL = createURL("output", "json3").PathAndQuery;
                string xmlURL = createURL("output", "xml").PathAndQuery;
                string xml2URL = createURL("output", "xml2").PathAndQuery;

                tw.Write("<div style='clear: both;'>");
                // Create a link to share this query with:
                tw.Write("<a class=\"button\" href=\"{0}\" target='_blank'>link</a>", HttpUtility.HtmlAttributeEncode(execURL));
                // Create a link to produce JSON output:
                tw.Write("&nbsp;<a class=\"button\" href=\"{0}\" target='_blank' title='Outputs JSON with rows as key-value objects; easiest for object-relational mapping scenario but column names may be appended with numeric suffixes in the event of non-unique keys'>JSON objects</a>", HttpUtility.HtmlAttributeEncode(jsonURL));
                tw.Write("&nbsp;<a class=\"button\" href=\"{0}\" target='_blank' title='Outputs JSON with rows as arrays of {{name, value}} pair objects; easiest for consuming in a metadata-oriented scenario but can be bloated'>JSON {{name, value}} pairs</a>", HttpUtility.HtmlAttributeEncode(json2URL));
                tw.Write("&nbsp;<a class=\"button\" href=\"{0}\" target='_blank' title='Outputs JSON with rows as arrays of raw values in column order; easiest for consuming raw data where column names are unimportant'>JSON arrays</a>", HttpUtility.HtmlAttributeEncode(json3URL));
                // Create a link to produce XML output:
                tw.Write("&nbsp;<a class=\"button\" href=\"{0}\" target='_blank' title='Outputs XML with columns as &lt;column name=\"column_name\"&gt;value&lt;/column&gt;; easiest to consume in a metadata-oriented scenario'>XML fixed elements</a>", HttpUtility.HtmlAttributeEncode(xmlURL));
                tw.Write("&nbsp;<a class=\"button\" href=\"{0}\" target='_blank' title='Outputs XML with columns as &lt;column_name&gt;value&lt;/column_name&gt; easiest for object-relational mapping scenario but column names are sanitized for XML compliance and may be appended with numeric suffixes in the event of uniqueness collisions'>XML named elements</a>", HttpUtility.HtmlAttributeEncode(xml2URL));
                tw.Write("</div>");

                // Timing information:
                tw.Write("<div style='clear: both;'>");
                tw.Write("<div style='float: left; margin-top: 1em'>");
                tw.Write("<strong>ROWCOUNT limit:</strong>&nbsp;{0}<br/>", rowLimit);
                tw.Write("<strong>Last executed:</strong>&nbsp;{1}<br/><strong>Execution time:</strong>&nbsp;{0:N0} ms<br/>", execTimeMsec, DateTimeOffset.Now);
                tw.Write("</div>");
                tw.Write("<div style='float: right;'>");
                tw.Write("<button id='toggleColumnTypeHeaders'>Show Types</button><br/>");
                tw.Write("</div>");
                tw.Write("</div>");

                // TABLE output:
                tw.Write("<div id='resultsTableDiv'>");
                tw.Write("<table id='resultsTable' border='1' cellspacing='0' cellpadding='2'>\n");

                int rowNumber = 1;
                foreach (IEnumerable<object> row in rows)
                {
                    if ((rowNumber - 1) % 10 == 0)
                    {
                        // Write header:
                        if (rowNumber > 1) tw.Write("</tbody>\n");
                        tw.Write("<thead><tr><th>Row</th>");
                        for (int h = 0; h <= header.GetUpperBound(0); ++h)
                        {
                            tw.Write("<th class='colname' colspan='2'>{0}</th><th class='coltype' style='display: none;'>{1}</th>", HttpUtility.HtmlEncode(header[h, 0]), HttpUtility.HtmlEncode(header[h, 1]));
                        }
                        tw.Write("</tr></thead>\n<tbody>");
                    }

                    tw.Write("<tr>");
                    tw.Write("<td class='rn'>{0}</td>", rowNumber++);

                    using (var rowen = row.GetEnumerator())
                        for (int colnum = 0; rowen.MoveNext(); ++colnum)
                        {
                            object col = rowen.Current;

                            string align = null;
                            bool isNobr = false, pre = false;
                            string tdclass = null;

                            // Use the SQL type to determine column alignment:
                            string sqltype = header[colnum, 1];
                            if (sqltype == "int" || sqltype == "decimal" || sqltype == "double" || sqltype == "money")
                                align = "right";
                            else if (sqltype == "datetime" || sqltype == "datetimeoffset" || sqltype == "datetime2")
                                isNobr = true;
                            else if (sqltype == "char")
                                pre = true;

                            // Allow request variables to override certain column formattings:
                            string q;
                            q = req[String.Format("_c{0}pre", colnum)];
                            if (q != null) pre = (q == "1");
                            q = req[String.Format("_c{0}align", colnum)];
                            if (q != null) align = q;
                            q = req[String.Format("_c{0}nobr", colnum)];
                            if (q != null) isNobr = (q == "1");

                            string colvalue;
                            if ((col == null) || (col == DBNull.Value))
                            {
                                // Display NULL value:
                                colvalue = "NULL";
                                tdclass = "nullvalue";
                            }
                            else
                            {
                                // Check type of the vaue:
                                Type ctype = col.GetType();
                                if (ctype == typeof(byte[]))
                                {
                                    // Display byte[] as 0xHEXCHARS:
                                    byte[] bytes = (byte[])col;
                                    colvalue = HttpUtility.HtmlEncode(toHexString(bytes));
                                    tdclass = "hexvalue";
                                }
                                else
                                {
                                    // All else, use TypeConverter.ConvertToString:
                                    var tc = System.ComponentModel.TypeDescriptor.GetConverter(ctype);
                                    colvalue = tc.ConvertToString(col);

                                    bool containsNewLines = (colvalue.IndexOfAny(new char[] { '\r', '\n' }) >= 0);

                                    colvalue = HttpUtility.HtmlEncode(colvalue);

                                    // Use a <nobr> around short-enough columns that include word-breaking chars.
                                    if ((colvalue.Length <= 60) && !containsNewLines)
                                        isNobr = true;

                                    // Convert '\n' to "<br/>":
                                    if (containsNewLines)
                                        colvalue = colvalue.Replace("\r", String.Empty).Replace("\n", "<br/>");
                                }
                            }

                            string attrs = String.Empty;
                            string wrapperElementStart = String.Empty;
                            string wrapperElementEnd = String.Empty;

                            if (tdclass != null) attrs += " class='" + tdclass + "'";
                            if (align != null) attrs += " style='text-align: " + align + ";'";
                            if (isNobr) { wrapperElementStart += "<nobr>"; wrapperElementEnd = "</nobr>" + wrapperElementEnd; }
                            if (pre) { wrapperElementStart += "<pre>"; wrapperElementEnd = "</pre>" + wrapperElementEnd; }

                            // NOTE: colvalue is HTML-encoded.
                            tw.Write("<td colspan='2'{1}>{2}{0}{3}</td>", colvalue, attrs, wrapperElementStart, wrapperElementEnd);
                        } // foreach (object col in row)

                    tw.Write("</tr>\n");
                } // foreach (IEnumerable<object> row in rows)

                tw.Write("</tbody>\n");
                tw.Write("</table>");

                tw.Write("</div>"); // id='resultsTableDiv'
                tw.Write("</div></div>");

            end:
                tw.Write("</div>\n"); // id='tab-results'
            }


            // Query log tab:
            {
                tw.Write("<div id='tab-log'>");

                const int pagesize = 20;

                int pagenumber;
                if (!Int32.TryParse(getFormOrQueryValue("pg"), out pagenumber))
                    pagenumber = 1;
                if (pagenumber < 1) pagenumber = 1;

                int pageindex = pagenumber - 1;

                // Load the log records in a lazy fashion:
                IEnumerable<string[]> logrecords = getLogRecords();

                // Pull up a page of log records:
                List<string[]> logpage = logrecords.Reverse().Skip(pageindex * pagesize).Take(pagesize).ToList();
                if (logpage.Count == 0)
                {
                    tw.Write("No log records.");
                    goto end;
                }

                tw.Write("<table border='0'>");
                tw.Write("<thead>");
                tw.Write("<tr><th>Date</th><th>Source</th><th>Execute</th><th>Query</th></tr>");
                tw.Write("</thead>");
                tw.Write("<tbody>");
                foreach (string[] row in logpage)
                {
                    // Parse the URL stored in the log and just render the link as self-relative. Only the query-string is important.
                    Uri execUrl;
                    string goUrl;
                    if (Uri.TryCreate(row[3], UriKind.Absolute, out execUrl))
                    {
                        goUrl = execUrl.PathAndQuery;
                    }
                    else
                    {
                        goUrl = row[3];
                    }

                    tw.Write("<tr>");
                    tw.Write("<td>{0}</td><td>{1}</td><td><a href=\"{3}\">GO</a></td><td><nobr><pre>{2}</pre></nobr></td>",
                        HttpUtility.HtmlEncode(row[0]),
                        HttpUtility.HtmlEncode(row[1]),
                        HttpUtility.HtmlEncode(row[2]),
                        HttpUtility.HtmlAttributeEncode(goUrl)
                    );
                    tw.Write("</tr>\n");
                }
                tw.Write("</tbody>\n");

                // Generate pager links:
                tw.Write("<tfoot>");
                string prevURL = createURL(new KeyValuePair<string, string>("action", "Log"), new KeyValuePair<string, string>("pg", (pagenumber - 1).ToString())).ToString();
                if (pagenumber > 1)
                    tw.Write("<a href=\"{0}\">", HttpUtility.HtmlAttributeEncode(prevURL));
                else
                    tw.Write("<span>");
                tw.Write("Prev {0}", pagesize);
                if (pagenumber > 1)
                    tw.Write("</a>&nbsp;");
                else
                    tw.Write("</span>&nbsp;");

                string nextURL = createURL(new KeyValuePair<string, string>("action", "Log"), new KeyValuePair<string, string>("pg", (pagenumber + 1).ToString())).ToString();
                if (logpage.Count == pagesize)
                    tw.Write("<a href=\"{0}\">", HttpUtility.HtmlAttributeEncode(nextURL));
                else
                    tw.Write("<span>");
                tw.Write("Next {0}", pagesize);
                if (logpage.Count == pagesize)
                    tw.Write("</a>");
                else
                    tw.Write("</span>");
                tw.Write("</tfoot>\n");

                tw.Write("</table>");

            end:
                tw.Write("</div>\n"); // id='tab-log'
            }


            // Self-update tool:
            {
                tw.Write("<div id='tab-self-update'><form method='POST'>");
                tw.Write("Self-update tool:&nbsp;<input type='submit' name='self-update' value='Update' onclick=\"javascript: return confirm('WARNING: This action will overwrite the current version of this tool with the latest version from github. Are you sure you want to do this?');\" />");
                tw.Write("</form>");
                if (message != null)
                {
                    tw.Write("<br/><strong>{0}</strong>", HttpUtility.HtmlEncode(message));
                }
                tw.Write("</div>\n"); // id='tab-self-update'
            }


            // End:
            tw.Write("</div>\n"); // id='tabs'
            tw.Write("</form></div>");

            // Footer:
            tw.Write("<div style='clear: both; float: right;'>");
#if Credits
            tw.Write("<span>&copy; Copyright 2011, <a href=\"https://github.com/JamesDunne\" target=\"_blank\">James S. Dunne</a></span><br/>");
#endif
#if TipJar
            // Tip jar!
            tw.Write("<span style='float: right;'>");
            tw.Write(@"<form action=""https://www.paypal.com/cgi-bin/webscr"" method=""post"">
<input type=""hidden"" name=""cmd"" value=""_s-xclick"">
<input type=""hidden"" name=""encrypted"" value=""-----BEGIN PKCS7-----MIIHLwYJKoZIhvcNAQcEoIIHIDCCBxwCAQExggEwMIIBLAIBADCBlDCBjjELMAkGA1UEBhMCVVMxCzAJBgNVBAgTAkNBMRYwFAYDVQQHEw1Nb3VudGFpbiBWaWV3MRQwEgYDVQQKEwtQYXlQYWwgSW5jLjETMBEGA1UECxQKbGl2ZV9jZXJ0czERMA8GA1UEAxQIbGl2ZV9hcGkxHDAaBgkqhkiG9w0BCQEWDXJlQHBheXBhbC5jb20CAQAwDQYJKoZIhvcNAQEBBQAEgYBF0gvvjaI1gyGdO6WLTfaYSS4QpIyDNYwrr0uC8XqGlw5VMva4bW1I9IBPZRIZNsT299NMyp0Nsdxe68Obg8kkknyjOggE9J1UJ+vb60gVBslNyTDmevIQJoJvQXpO5Qb+yQBw2wHQXXu3R2L6G8mdHroa+tc88GOeN915W6HJIzELMAkGBSsOAwIaBQAwgawGCSqGSIb3DQEHATAUBggqhkiG9w0DBwQIaALpX0YWNfKAgYjc8xioL68E9NxGAx8cppEuAkae6NKABuh/Tj2yaoYylj3y//AediZXJXizunV+6PEzMT2AhyeFcktASFXj50imvKgoYCWDwI8fuOTa8wJZpw0hB730hNFZvQk/HO8dhGHGizQXI5XGr2IDJcwY86rvdERiVF1PsRz8Hs3P1a83pqKabyz8Ui2coIIDhzCCA4MwggLsoAMCAQICAQAwDQYJKoZIhvcNAQEFBQAwgY4xCzAJBgNVBAYTAlVTMQswCQYDVQQIEwJDQTEWMBQGA1UEBxMNTW91bnRhaW4gVmlldzEUMBIGA1UEChMLUGF5UGFsIEluYy4xEzARBgNVBAsUCmxpdmVfY2VydHMxETAPBgNVBAMUCGxpdmVfYXBpMRwwGgYJKoZIhvcNAQkBFg1yZUBwYXlwYWwuY29tMB4XDTA0MDIxMzEwMTMxNVoXDTM1MDIxMzEwMTMxNVowgY4xCzAJBgNVBAYTAlVTMQswCQYDVQQIEwJDQTEWMBQGA1UEBxMNTW91bnRhaW4gVmlldzEUMBIGA1UEChMLUGF5UGFsIEluYy4xEzARBgNVBAsUCmxpdmVfY2VydHMxETAPBgNVBAMUCGxpdmVfYXBpMRwwGgYJKoZIhvcNAQkBFg1yZUBwYXlwYWwuY29tMIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDBR07d/ETMS1ycjtkpkvjXZe9k+6CieLuLsPumsJ7QC1odNz3sJiCbs2wC0nLE0uLGaEtXynIgRqIddYCHx88pb5HTXv4SZeuv0Rqq4+axW9PLAAATU8w04qqjaSXgbGLP3NmohqM6bV9kZZwZLR/klDaQGo1u9uDb9lr4Yn+rBQIDAQABo4HuMIHrMB0GA1UdDgQWBBSWn3y7xm8XvVk/UtcKG+wQ1mSUazCBuwYDVR0jBIGzMIGwgBSWn3y7xm8XvVk/UtcKG+wQ1mSUa6GBlKSBkTCBjjELMAkGA1UEBhMCVVMxCzAJBgNVBAgTAkNBMRYwFAYDVQQHEw1Nb3VudGFpbiBWaWV3MRQwEgYDVQQKEwtQYXlQYWwgSW5jLjETMBEGA1UECxQKbGl2ZV9jZXJ0czERMA8GA1UEAxQIbGl2ZV9hcGkxHDAaBgkqhkiG9w0BCQEWDXJlQHBheXBhbC5jb22CAQAwDAYDVR0TBAUwAwEB/zANBgkqhkiG9w0BAQUFAAOBgQCBXzpWmoBa5e9fo6ujionW1hUhPkOBakTr3YCDjbYfvJEiv/2P+IobhOGJr85+XHhN0v4gUkEDI8r2/rNk1m0GA8HKddvTjyGw/XqXa+LSTlDYkqI8OwR8GEYj4efEtcRpRYBxV8KxAW93YDWzFGvruKnnLbDAF6VR5w/cCMn5hzGCAZowggGWAgEBMIGUMIGOMQswCQYDVQQGEwJVUzELMAkGA1UECBMCQ0ExFjAUBgNVBAcTDU1vdW50YWluIFZpZXcxFDASBgNVBAoTC1BheVBhbCBJbmMuMRMwEQYDVQQLFApsaXZlX2NlcnRzMREwDwYDVQQDFAhsaXZlX2FwaTEcMBoGCSqGSIb3DQEJARYNcmVAcGF5cGFsLmNvbQIBADAJBgUrDgMCGgUAoF0wGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcNMTExMDIxMjAzNjA1WjAjBgkqhkiG9w0BCQQxFgQUC6LMhGKHeiXR6bzfu5YkvmsolCIwDQYJKoZIhvcNAQEBBQAEgYB+rfBdfq/6sOYYxJmGvR4Px+s0tuIvBcxAuZJREuD8DddXjPhNja1d4JC3M8S1SJ4JXpi6juQcrdAr4jRLXOgAOs4zU+n4GUiiSbulKEYDb9o2pMqlgBbnGqDgwtp5vPjcZT2viYEbUUXEYbcVXaIzUWkK8LD7FZOwO5mAGIRwAw==-----END PKCS7-----
"">
<input type=""image"" src=""https://www.paypalobjects.com/en_US/i/btn/btn_donate_SM.gif"" border=""0"" name=""submit"" alt=""PayPal - The safer, easier way to pay online!"">
<img alt="""" border=""0"" src=""https://www.paypalobjects.com/en_US/i/scr/pixel.gif"" width=""1"" height=""1"">
</form>");
            tw.Write("</span>");
            tw.Write("<span style='float: right;'>Tip jar:&nbsp;</span>");
#endif
            tw.Write("</div>\n");

            tw.Write("</body></html>");
        }

        private Uri createURL(string key, string value)
        {
            return createURL(new KeyValuePair<string, string>(key, value));
        }

        private Uri createURL(params KeyValuePair<string, string>[] qvs)
        {
            var req = ctx.Request;

            // Create a UriBuilder based on the current request Uri that overrides the query-string:
            UriBuilder nextUri = new UriBuilder(req.Url);

            var kvpairs = (
                from key in req.Form.AllKeys.Union(req.QueryString.AllKeys)
                let values = getFormOrQueryValues(key)
                where values.Any()
                where (values.Length > 1) || ((values.Length == 1) && !String.IsNullOrEmpty(values[0]))
                from value in values
                select new KeyValuePair<string, string>(key, value)
            ).ToList();

            // Set new key/value pairs:
            foreach (var qv in qvs)
            {
                int idx = kvpairs.FindIndex(kv => kv.Key == qv.Key);

                if (idx == -1)
                    kvpairs.Add(qv);
                else
                    kvpairs[idx] = qv;
            }

            // Rebuild the query string:
            nextUri.Query = String.Join("&", kvpairs.Select(kv => HttpUtility.UrlEncode(kv.Key) + "=" + HttpUtility.UrlEncode(kv.Value)).ToArray());

            return nextUri.Uri;
        }

        private bool convertParameters(out ParameterValue[] parameters)
        {
            // Validate parameters:
            string[] prmNames, prmTypes, prmValues;
            prmNames = getFormOrQueryValues("pn") ?? new string[0];
            prmTypes = getFormOrQueryValues("pt") ?? new string[0];
            prmValues = getFormOrQueryValues("pv") ?? new string[0];

            System.Diagnostics.Debug.Assert(prmNames.Length == prmTypes.Length);
            System.Diagnostics.Debug.Assert(prmTypes.Length == prmValues.Length);

            bool parametersValid = true;
            parameters = new ParameterValue[prmNames.Length];

            for (int i = 0; i < prmNames.Length; ++i)
            {
                parameters[i] = new ParameterValue(prmNames[i], prmTypes[i], prmValues[i]);
                if (!parameters[i].IsValid) parametersValid = false;
            }

            return parametersValid;
        }

        private static string generateOptionList(string[] options)
        {
            return generateOptionList(options, null);
        }

        private static string generateOptionList(string[] options, string selected)
        {
            // Predict enough space to generate the option list:
            StringBuilder sb = new StringBuilder(options.Sum(opt => "<option></option>".Length + opt.Length) + " selected='selected'".Length);
            for (int i = 0; i < options.Length; ++i)
                sb.AppendFormat("<option{1}>{0}</option>",
                    HttpUtility.HtmlEncode(options[i]),
                    (options[i] == selected)
                    ? " selected='selected'"
                    : String.Empty
                );
            return sb.ToString();
        }

        private static string javascriptStringEncode(string text)
        {
            return text.Replace("'", "\\'");
        }

        private static string toHexString(byte[] bytes)
        {
            const string hexChars = "0123456789ABCDEF";

            StringBuilder sbhex = new StringBuilder(2 + 2 * bytes.Length);
            sbhex.Append("0x");
            for (int j = 0; j < bytes.Length; ++j)
            {
                sbhex.Append(hexChars[bytes[j] >> 4]);
                sbhex.Append(hexChars[bytes[j] & 0xF]);
            }
            return sbhex.ToString();
        }

        private enum JsonOutput
        {
            Dictionary,
            KeyValuePair,
            Array
        }

        private void renderJSON(JsonOutput mode, bool noQuery, bool noHeader)
        {
            rsp.StatusCode = 200;
            rsp.ContentType = "application/json";
            rsp.ContentEncoding = Encoding.UTF8;
            //rsp.BufferOutput = false;

            System.IO.TextWriter tw = rsp.Output;

            string csname, cs, withCTEidentifier, withCTEexpression, select, from, where, groupBy, having, orderBy;

            // Pull FORM values:
            csname = getFormOrQueryValue("csname");
            cs = getFormOrQueryValue("cs");
            withCTEidentifier = getFormOrQueryValue("wi");
            withCTEexpression = getFormOrQueryValue("we");
            select = getFormOrQueryValue("select");
            from = getFormOrQueryValue("from");
            where = getFormOrQueryValue("where");
            groupBy = getFormOrQueryValue("groupBy");
            having = getFormOrQueryValue("having");
            orderBy = getFormOrQueryValue("orderBy");

            string callback = getFormOrQueryValue("callback");

            // Validate and convert parameters:
            ParameterValue[] parameters;
            bool parametersValid = convertParameters(out parameters);

            string query;
            string[,] header;
            IEnumerable<IEnumerable<object>> rows;
            long execTimeMsec;

            // Execute the query:
            string errMessage;
            try
            {
                errMessage = QuerySQL(csname, cs, withCTEidentifier, withCTEexpression, select, from, where, groupBy, having, orderBy, parameters, out query, out header, out execTimeMsec, out rows);
            }
            catch (Exception ex)
            {
                errMessage = ex.Message;
                query = null;
                execTimeMsec = 0;
                rows = null;
                header = null;
            }

            var jss = new System.Web.Script.Serialization.JavaScriptSerializer();
            var final = new Dictionary<string, object>();

            if (!noQuery && query != null)
            {
                var query_parts = new Dictionary<string, object>();

                if (!String.IsNullOrEmpty(withCTEidentifier))
                    query_parts.Add("with_cte_identifier", withCTEidentifier);
                if (!String.IsNullOrEmpty(withCTEexpression))
                    query_parts.Add("with_cte_expression", withCTEexpression);
                query_parts.Add("select", select);
                if (!String.IsNullOrEmpty(from))
                    query_parts.Add("from", from);
                if (!String.IsNullOrEmpty(where))
                    query_parts.Add("where", where);
                if (!String.IsNullOrEmpty(groupBy))
                    query_parts.Add("groupBy", groupBy);
                if (!String.IsNullOrEmpty(having))
                    query_parts.Add("having", having);
                if (!String.IsNullOrEmpty(orderBy))
                    query_parts.Add("orderBy", orderBy);
                final.Add("query_parts", query_parts);

                final.Add("query", query);

                // FIXME? value is always a raw string value. This is good for decimal/money types, maybe not so great for everything else.
                final.Add("parameters", parameters.Select(prm => new { name = prm.Name, type = prm.RawType, value = prm.RawValue }).ToArray());
            }

            if (errMessage != null)
            {
                // TODO: more verbose error reporting
                final.Add("error", new Dictionary<string, object> { { "message", errMessage } });
                if (callback != null)
                {
                    tw.Write(callback);
                    tw.Write('(');
                }
                tw.Write(jss.Serialize(final));
                if (callback != null) tw.Write(");");
                return;
            }

            final.Add("time", execTimeMsec);
            getJSONDictionary(final, mode, noQuery, noHeader, header, rows);

            if (callback != null)
            {
                tw.Write(callback);
                tw.Write('(');
            }
            tw.Write(jss.Serialize(final));
            if (callback != null) tw.Write(");");
        }

        private void getJSONDictionary(Dictionary<string, object> final, JsonOutput mode, bool noQuery, bool noHeader, string[,] header, IEnumerable<IEnumerable<object>> rows)
        {
            // Convert the header string[,] to { name, type }[]:
            List<object> headers = new List<object>(header.GetUpperBound(0) + 1);
            string[] uniqname = new string[header.GetUpperBound(0) + 1];
            HashSet<string> namesSet = new HashSet<string>();

            for (int i = 0; i <= header.GetUpperBound(0); ++i)
            {
                headers.Add(new { name = header[i, 0], type = header[i, 1], ordinal = i });

                if (mode == JsonOutput.Dictionary)
                {
                    // Generate a unique name for this column:
                    string jsonname = header[i, 0];
                    if (jsonname == String.Empty) jsonname = "blank";

                    string name = jsonname;

                    int ctr = 0;
                    while (namesSet.Contains(name)) name = jsonname + "_" + (++ctr).ToString();

                    namesSet.Add(name);
                    uniqname[i] = name;
                }
            }

            if (!noHeader)
            {
                final.Add("header", headers);
            }

            // Convert each result row:
            object results;
            if (mode == JsonOutput.Dictionary)
            {
                var list = new List<Dictionary<string, object>>();
                foreach (IEnumerable<object> row in rows)
                {
                    var result = new Dictionary<string, object>();

                    // { "colname1": "value1", "colname2": "value2" ... }
                    using (var rowen = row.GetEnumerator())
                        for (int i = 0; rowen.MoveNext(); ++i)
                        {
                            object col = rowen.Current;
                            // TODO: convert DateTime values so we don't end up with the MS "standard" '\/Date()\/' format.

                            result.Add(uniqname[i], col);
                        }

                    list.Add(result);
                }
                results = list;
            }
            else if (mode == JsonOutput.KeyValuePair)
            {
                var list = new List<object>();
                foreach (IEnumerable<object> row in rows)
                {
                    var result = new List<Dictionary<string, object>>();

                    // [ { "name": "col1", "value": 1 }, { "name": "col2", "value": null } ... ]
                    using (var rowen = row.GetEnumerator())
                        for (int i = 0; rowen.MoveNext(); ++i)
                        {
                            object col = rowen.Current;
                            // TODO: convert DateTime values so we don't end up with the MS "standard" '\/Date()\/' format.

                            result.Add(new Dictionary<string, object> { { "name", header[i, 0] }, { "value", col } });
                        }

                    list.Add(result);
                }
                results = list;
            }
            else if (mode == JsonOutput.Array)
            {
                var list = new List<List<object>>();
                foreach (IEnumerable<object> row in rows)
                {
                    var result = new List<object>();

                    // [ value1, value2, value3, ... ]
                    using (var rowen = row.GetEnumerator())
                        for (int i = 0; rowen.MoveNext(); ++i)
                        {
                            object col = rowen.Current;
                            // TODO: convert DateTime values so we don't end up with the MS "standard" '\/Date()\/' format.

                            result.Add(col);
                        }

                    list.Add(result);
                }
                results = list;
            }
            else
            {
                results = "Unknown JSON mode!";
            }

            final.Add("results", results);
        }

        private enum XmlOutput
        {
            FixedColumns,
            NamedColumns
        }

        private void renderXML(XmlOutput mode, bool noQuery, bool noHeader)
        {
            rsp.StatusCode = 200;
            rsp.ContentType = "application/xml";
            rsp.ContentEncoding = Encoding.UTF8;
            //rsp.BufferOutput = false;

            System.IO.TextWriter tw = rsp.Output;

            string csname, cs, withCTEidentifier, withCTEexpression, select, from, where, groupBy, having, orderBy;

            // Pull FORM values:
            csname = getFormOrQueryValue("csname");
            cs = getFormOrQueryValue("cs");
            withCTEidentifier = getFormOrQueryValue("wi");
            withCTEexpression = getFormOrQueryValue("we");
            select = getFormOrQueryValue("select");
            from = getFormOrQueryValue("from");
            where = getFormOrQueryValue("where");
            groupBy = getFormOrQueryValue("groupBy");
            having = getFormOrQueryValue("having");
            orderBy = getFormOrQueryValue("orderBy");

            // Validate and convert parameters:
            ParameterValue[] parameters;
            bool parametersValid = convertParameters(out parameters);

            string query;
            string[,] header;
            IEnumerable<IEnumerable<object>> rows;
            long execTimeMsec;

            // Execute the query:
            string errMessage;
            try
            {
                errMessage = QuerySQL(csname, cs, withCTEidentifier, withCTEexpression, select, from, where, groupBy, having, orderBy, parameters, out query, out header, out execTimeMsec, out rows);
            }
            catch (Exception ex)
            {
                errMessage = ex.Message;
                query = null;
                execTimeMsec = 0;
                rows = null;
                header = null;
            }

            using (var xw = new System.Xml.XmlTextWriter(tw))
            {
                xw.WriteStartElement("response");

                // Probably a security risk?
                //xw.WriteElementString("connection_string", cs);
                //xw.WriteElementString("connection_string_name", csname);

                if (!noQuery)
                {
                    xw.WriteStartElement("query_parts");

                    if (!String.IsNullOrEmpty(withCTEidentifier))
                        xw.WriteElementString("with_cte_identifier", withCTEidentifier);
                    if (!String.IsNullOrEmpty(withCTEexpression))
                        xw.WriteElementString("with_cte_expression", withCTEexpression);
                    xw.WriteElementString("select", select);
                    if (!String.IsNullOrEmpty(from))
                        xw.WriteElementString("from", from);
                    if (!String.IsNullOrEmpty(where))
                        xw.WriteElementString("where", where);
                    if (!String.IsNullOrEmpty(groupBy))
                        xw.WriteElementString("groupBy", groupBy);
                    if (!String.IsNullOrEmpty(having))
                        xw.WriteElementString("having", having);
                    if (!String.IsNullOrEmpty(orderBy))
                        xw.WriteElementString("orderBy", orderBy);
                    xw.WriteEndElement(); // query_parts

                    xw.WriteElementString("query", query);

                    xw.WriteStartElement("parameters");
                    foreach (var prm in parameters)
                    {
                        xw.WriteStartElement("parameter");
                        xw.WriteAttributeString("name", prm.Name);
                        xw.WriteAttributeString("type", prm.RawType);
                        xw.WriteString(prm.RawValue);
                        xw.WriteEndElement(); // parameter
                    }
                    xw.WriteEndElement(); // parameters
                }

                // Handle errors:
                if (errMessage != null)
                {
                    xw.WriteElementString("error", errMessage);
                    goto end;
                }

                xw.WriteElementString("time", execTimeMsec.ToString());

                // Convert the header string[,] to { name, type }[]:
                string[] uniqname = new string[header.GetUpperBound(0) + 1];
                HashSet<string> namesSet = new HashSet<string>();

                if (!noHeader) xw.WriteStartElement("header");
                for (int i = 0; i <= header.GetUpperBound(0); ++i)
                {
                    // Generate a unique name for this column:
                    string xmlname = scrubForXml(header[i, 0]);
                    if (xmlname == String.Empty) xmlname = "blank";

                    string name = xmlname;

                    int ctr = 0;
                    while (namesSet.Contains(name)) name = xmlname + "_" + (++ctr).ToString();

                    namesSet.Add(name);
                    uniqname[i] = name;

                    if (!noHeader)
                    {
                        xw.WriteStartElement("column");
                        xw.WriteAttributeString("name", name);
                        xw.WriteAttributeString("type", header[i, 1]);
                        xw.WriteAttributeString("ordinal", i.ToString());
                        xw.WriteEndElement(); // column
                    }
                }
                if (!noHeader) xw.WriteEndElement(); // header

                xw.WriteStartElement("results");
                foreach (IEnumerable<object> row in rows)
                {
                    xw.WriteStartElement("row");
                    using (var rowen = row.GetEnumerator())
                        for (int i = 0; rowen.MoveNext(); ++i)
                        {
                            object col = rowen.Current;
                            if (col == null)
                            {
                                if (mode == XmlOutput.NamedColumns)
                                {
                                    // TODO: output xsi:nil="true"
                                    xw.WriteElementString(uniqname[i], null);
                                }
                                else if (mode == XmlOutput.FixedColumns)
                                {
                                    xw.WriteStartElement("column");
                                    xw.WriteAttributeString("name", header[i, 0]);
                                    // TODO: output xsi:nil="true"
                                    xw.WriteEndElement(); // column
                                }
                                else
                                {
                                    throw new NotImplementedException("Unknown XML output mode");
                                }
                                continue;
                            }

                            string colvalue;

                            // Check type of the vaue:
                            Type ctype = col.GetType();
                            if (ctype == typeof(byte[]))
                            {
                                // Display byte[] as 0xHEXCHARS:
                                byte[] bytes = (byte[])col;
                                colvalue = toHexString(bytes);
                            }
                            else
                            {
                                // All else, use TypeConverter.ConvertToString:
                                var tc = System.ComponentModel.TypeDescriptor.GetConverter(ctype);
                                colvalue = tc.ConvertToString(col);
                            }

                            if (mode == XmlOutput.NamedColumns)
                            {
                                xw.WriteElementString(uniqname[i], colvalue);
                            }
                            else if (mode == XmlOutput.FixedColumns)
                            {
                                xw.WriteStartElement("column");
                                xw.WriteAttributeString("name", header[i, 0]);
                                xw.WriteString(colvalue);
                                xw.WriteEndElement(); // column
                            }
                            else
                            {
                                throw new NotImplementedException("Unknown XML output mode");
                            }
                        }

                    xw.WriteEndElement(); // row
                }
                xw.WriteEndElement(); // results

            end:
                xw.WriteEndElement(); // response
            }
        }

        private static string scrubForXml(string name)
        {
            if (name == null) return String.Empty;
            if (name.Length == 0) return String.Empty;

            StringBuilder sb = new StringBuilder(name.Length);

            char c = name[0];
            if (!Char.IsLetter(c) && c != '_')
                sb.Append('_');
            else
                sb.Append(c);

            for (int i = 1; i < name.Length; ++i)
            {
                c = name[i];
                if (!Char.IsLetterOrDigit(c) && c != '_')
                    sb.Append('_');
                else
                    sb.Append(c);
            }

            return sb.ToString();
        }

        private void errorResponse(int statusCode, string messageFormat, params object[] args)
        {
            rsp.Clear();
            rsp.StatusCode = statusCode;
            rsp.ContentType = "application/json";
            var final = new Dictionary<string, object> {
                { "error", new Dictionary<string, object> {
                    { "message", String.Format(messageFormat, args) }
                } }
            };
            // Serialize the dictionary to JSON:
            var jss = new System.Web.Script.Serialization.JavaScriptSerializer();
            string json = jss.Serialize(final);
            rsp.Write(json);
        }

        // Handle data modification commands securely.
        private void modifyCommit(bool doCommit)
        {
            string cmd = req.Form["c"];
            string query = req.Form["q"];
            string connString = getFormOrQueryValue("cs");

            // All fields are required input:
            if (String.IsNullOrEmpty(cmd)
             || String.IsNullOrEmpty(query)
             || String.IsNullOrEmpty(connString))
            {
                errorResponse(403, "A required input field is missing");
                return;
            }

            // Verify that the user is who he says he is:
            string pubkey64;
            if (!verifyAuthorization(() => Encoding.UTF8.GetBytes(cmd + "\n" + query), out pubkey64))
                return;

            // Client is now verified to hold the private key paired with the public key they gave us.

            string rowlimitStr = getFormOrQueryValue("rowlimit");
            if ((rowlimitStr != null) && !Int32.TryParse(rowlimitStr, out rowLimit))
            {
                // If parsing failed, reset the rowLimit to the default:
                rowLimit = defaultRowLimit;
            }

            try
            {
                // NOTE: allowing any data modification command except DDL statements
                cmd = stripSQLComments(cmd);
                if (containsSQLkeywords(cmd, "commit", "rollback", "create", "drop", "begin"))
                {
                    errorResponse(403, "Command contains restricted keywords");
                    return;
                }

                // NOTE: assuming a SELECT query
                query = stripSQLComments(query);
                if (containsSQLkeywords(query, "commit", "rollback", "delete", "insert", "update", "create", "drop", "into"))
                {
                    errorResponse(403, "Query contains restricted keywords");
                    return;
                }
            }
            catch (Exception ex)
            {
                errorResponse(403, ex.Message);
                return;
            }
            
            // Build the SQL command to execute:
            string cmdtext =
@"BEGIN TRAN

" + cmd + @";

" + query + @";

" + (doCommit ? "COMMIT TRAN" : "ROLLBACK TRAN");

            Exception error;
            long timeMsec;
            string[,] header;
            IEnumerable<IEnumerable<object>> results;

            var final = new Dictionary<string, object>();

            // Execute the command:
            bool execSuccess = executeQuery(connString, cmdtext, out timeMsec, out header, out results, out error);

            // Render the results to JSON:

            if (!execSuccess)
            {
                rsp.StatusCode = 500;
                if (error is System.Data.SqlClient.SqlException)
                {
                    // Detailed SQL logging to JSON:
                    System.Data.SqlClient.SqlException sqex = (System.Data.SqlClient.SqlException)error;
                    final.Add("error", new Dictionary<string, object>
                    {
                        { "message",    sqex.Message },
                        { "line",       sqex.LineNumber },
                        { "server",     sqex.Server },
                        { "procedure",  sqex.Procedure },
                        { "code",       "0x" + String.Join("", BitConverter.GetBytes(unchecked((uint)sqex.ErrorCode)).Reverse().Select(b => b.ToString("X2")).ToArray()) },
                        { "class",      (int)sqex.Class },
                        { "number",     sqex.Number },
                        { "state",      (int)sqex.State },
                    });
                }
                else
                    // Default error handling:
                    final.Add("error", new Dictionary<string, object>
                    {
                        { "message",    error.Message }
                    });
            }
            else
            {
                rsp.StatusCode = 200;
                final.Add("time", timeMsec);
                final.Add("command", cmdtext);
                getJSONDictionary(final, JsonOutput.Array, true, false, header, results);
            }

            // Serialize the dictionary to JSON:
            var jss = new System.Web.Script.Serialization.JavaScriptSerializer();
            string json = jss.Serialize(final);

            // Write the response:
            rsp.ContentType = "application/json";
            rsp.ContentEncoding = Encoding.UTF8;
            rsp.Output.Write(json);
        }

        // Adds a new public key to the authorized keys file.
        private void addPublicKey()
        {
            string newpubkey64 = cleanBase64(req.Form["n"]);

            // All fields are required input:
            if (String.IsNullOrEmpty(newpubkey64))
            {
                errorResponse(403, "A required input field is missing");
                return;
            }

            // Validate that the to-be-added public key is RSA:
            string errorMessage;
            if (!isKeyValidFormat(newpubkey64, out errorMessage))
            {
                errorResponse(403, "New public key error: " + errorMessage);
                return;
            }

            // Normalize the BASE64 formatting for consistent comparison operation:
            newpubkey64 = pubkeyToBase64(pubkeyFromBase64(newpubkey64));

            // Verify that the user is who he says he is:
            string pubkey64;
            if (!verifyAuthorization(() => Convert.FromBase64String(newpubkey64), out pubkey64))
                return;

            // Client is now verified to hold the private key paired with the public key they gave us.

            // Add the new public key to the authorized keys file if it doesn't already exist:
            string status = addKeyToAuthorizedFile(newpubkey64);

            rsp.StatusCode = 200;
            rsp.Output.Write("Authorizing public key '{0}': {1}", newpubkey64, status);
        }

        // Revokes a public key from the authorized keys file.
        private void revokePublicKey()
        {
            string newpubkey64 = cleanBase64(req.Form["n"]);

            // All fields are required input:
            if (String.IsNullOrEmpty(newpubkey64))
            {
                errorResponse(403, "A required input field is missing");
                return;
            }

            // Validate that the to-be-added public key is RSA:
            string errorMessage;
            if (!isKeyValidFormat(newpubkey64, out errorMessage))
            {
                errorResponse(403, "Revocation public key error: " + errorMessage);
                return;
            }

            // Normalize the BASE64 formatting for consistent comparison operation:
            newpubkey64 = pubkeyToBase64(pubkeyFromBase64(newpubkey64));

            // Verify that the user is who he says he is:
            string pubkey64;
            if (!verifyAuthorization(() => Convert.FromBase64String(newpubkey64), out pubkey64))
                return;

            // Client is now verified to hold the private key paired with the public key they gave us.

            // Revoke the public key from the authorized keys file if it doesn't already exist:
            string status = revokeKeyFromAuthorizedFile(newpubkey64);

            rsp.StatusCode = 200;
            rsp.Output.Write("Revoking public key '{0}': {1}", newpubkey64, status);
        }

        private bool verifyAuthorization(Func<byte[]> getDataToSign, out string pubkey64)
        {
            if (!String.Equals(req.HttpMethod, "POST", StringComparison.OrdinalIgnoreCase))
            {
                errorResponse(405, "POST method expected");
                pubkey64 = null;
                return false;
            }

            string errorMessage;

            // Grab the user's public key and the signed (encrypted) data:
            pubkey64 = cleanBase64(req.Form["p"]);
            string timestampStr = req.Form["ts"];
            string signed64 = cleanBase64(req.Form["s"]);

            // All fields are required input:
            if (String.IsNullOrEmpty(pubkey64)
             || String.IsNullOrEmpty(signed64)
             || String.IsNullOrEmpty(timestampStr))
            {
                errorResponse(403, "A required input field is missing");
                return false;
            }

            // Verify the timestamp:
            long timestampTicks;
            if (!long.TryParse(timestampStr, out timestampTicks))
            {
                errorResponse(403, "Could not parse timestamp");
                return false;
            }

            // Combat replay attacks by verifying the timestamp is within a +/- 5 second window.
            long currTimestamp = DateTime.UtcNow.Ticks;
            if ((timestampTicks < (currTimestamp - (TimeSpan.TicksPerSecond * 5L)))
              || (timestampTicks > (currTimestamp + (TimeSpan.TicksPerSecond * 5L))))
            {
                errorResponse(403, "Timestamp out of range");
                return false;
            }

            // Validate that the new public key is RSA:
            if (!isKeyValidFormat(pubkey64, out errorMessage))
            {
                errorResponse(403, errorMessage);
                return false;
            }

            // Normalize the BASE64 formatting for consistent comparison operation:
            pubkey64 = pubkeyToBase64(pubkeyFromBase64(pubkey64));

            // Check that the public key is in the authorized keys list:
            if (!isKeyAuthorized(pubkey64))
            {
                errorResponse(403, "Public key '{0}' not authorized", pubkey64);
                return false;
            }

            // Client's public key is an authorized user; now let's verify that the client sending us the public key actually holds the paired private key:
            RSAParameters clientpubkey = pubkeyFromBase64(pubkey64);

            // Verify the signed data:
            byte[] signed = Convert.FromBase64String(signed64);
            byte[] toSign = BitConverter.GetBytes(timestampTicks).Concat(getDataToSign()).ToArray();
            if (!verifySignedHashWithKey(toSign, signed, clientpubkey))
            {
                errorResponse(403, "Public key could not be verified against signed data");
                return false;
            }

            return true;
        }

        private bool executeQuery(string connString, string query, out long timeMsec, out string[,] header, out IEnumerable<IEnumerable<object>> results, out Exception error)
        {
            // Open a connection and execute the command:
            var conn = new System.Data.SqlClient.SqlConnection(connString);
            var cmd = conn.CreateCommand();
            System.Data.SqlClient.SqlDataReader dr;

            try
            {
                conn.Open();

                // Set the TRANSACTION ISOLATION LEVEL to READ UNCOMMITTED so that we don't block any application queries:
                var tmpcmd = conn.CreateCommand();
                tmpcmd.CommandText = "SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;";
                tmpcmd.ExecuteNonQuery();

                // Set the ROWCOUNT so we don't overload the connection with too many results:
                if (rowLimit > 0)
                {
                    tmpcmd.CommandText = String.Format("SET ROWCOUNT {0};", rowLimit);
                    tmpcmd.ExecuteNonQuery();
                }

                cmd.CommandText = query;
                cmd.CommandType = System.Data.CommandType.Text;
                cmd.CommandTimeout = 360;   // seconds

                // Open a data reader to read the results:
                System.Diagnostics.Stopwatch swTimer = System.Diagnostics.Stopwatch.StartNew();
                dr = cmd.ExecuteReader(System.Data.CommandBehavior.CloseConnection | System.Data.CommandBehavior.SequentialAccess);
                swTimer.Stop();
                timeMsec = swTimer.ElapsedMilliseconds;
            }
            catch (Exception ex)
            {
                conn.Close();
                cmd.Dispose();

                // Set the exception and failed return:
                header = null;
                results = null;
                timeMsec = -1L;
                error = ex;
                return false;
            }

            // Get the header column names/types:
            header = getHeader(dr);
            // Get an enumerator over the results:
            results = enumerateResults(conn, cmd, dr);

            // Successful return:
            error = null;
            return true;
        }

        #region Encryption utilities

        private static string cleanBase64(string base64)
        {
            // Remove all whitespace:
            return base64.Replace("\n", "").Replace("\r", "").Replace(" ", "").Replace("\t", "").Trim();
        }

        private string KeysPath { get { return ctx.Server.MapPath(ctx.Request.AppRelativeCurrentExecutionFilePath + ".keys"); } }

        private bool isKeyAuthorized(string pubkeyBase64)
        {
            string[] authKeys = defaultAuthorizedPublicKeys;
            if (System.IO.File.Exists(KeysPath))
            {
                authKeys = authKeys.Concat(
                    from line in System.IO.File.ReadAllLines(KeysPath, Encoding.ASCII)
                    where !String.IsNullOrEmpty(line)
                    select line
                ).ToArray();
            }
            return authKeys.Contains(pubkeyBase64);
        }

        private string addKeyToAuthorizedFile(string newpubkey64)
        {
            string[] authKeys = defaultAuthorizedPublicKeys;
            if (System.IO.File.Exists(KeysPath))
            {
                authKeys = authKeys.Concat(
                    from line in System.IO.File.ReadAllLines(KeysPath, Encoding.ASCII)
                    where !String.IsNullOrEmpty(line)
                    select line
                ).ToArray();
            }
            // If the key is already authorized, don't add it again:
            if (authKeys.Contains(newpubkey64))
            {
                return "Key is already authorized";
            }

            using (var appender = System.IO.File.AppendText(KeysPath))
            {
                appender.WriteLine(newpubkey64);
            }

            return "Key successfully added";
        }

        private string revokeKeyFromAuthorizedFile(string newpubkey64)
        {
            string[] authKeys = defaultAuthorizedPublicKeys;
            if (authKeys.Contains(newpubkey64))
            {
                return "Cannot revoke a master key";
            }

            try
            {
                using (var tr = new System.IO.StreamReader(KeysPath, Encoding.UTF8))
                using (var tw = new System.IO.StreamWriter(KeysPath + ".tmp", false, Encoding.UTF8))
                {
                    string line;
                    bool found = false;
                    while ((line = tr.ReadLine()) != null)
                    {
                        if (line == newpubkey64)
                            found = true;
                        else
                            tw.WriteLine(line);
                    }
                    if (!found)
                    {
                        return "Could not find public key to revoke";
                    }
                }
            }
            finally
            {
                System.IO.File.Delete(KeysPath);
                System.IO.File.Move(KeysPath + ".tmp", KeysPath);
            }

            return "Key successfully revoked";
        }

        private static byte[] itobNetwork(int i)
        {
            return BitConverter.GetBytes(System.Net.IPAddress.HostToNetworkOrder(i));
        }

        private static int btoiNetwork(byte[] b, int startIndex)
        {
            return System.Net.IPAddress.NetworkToHostOrder(BitConverter.ToInt32(b, startIndex));
        }

        private static bool isKeyValidFormat(string pubkey64, out string message)
        {
            // Validate that the public key is RSA formatted and valid:
            try
            {
                RSAParameters tmp = pubkeyFromBase64(pubkey64);
            }
            catch (ArgumentException aex)
            {
                message = aex.Message;
                return false;
            }
            message = null;
            return true;
        }

        const string keytype = "ssh-rsa";

        private static string pubkeyToBase64(RSAParameters key)
        {
            // OpenSSL standard of serializing a public key to BASE64
            int keytypelen = keytype.Length;
            byte[] raw = new byte[4 + keytypelen + 4 + key.Exponent.Length + 4 + key.Modulus.Length];
            Array.Copy(itobNetwork((int)keytypelen), 0, raw, 0, 4);
            Array.Copy(Encoding.ASCII.GetBytes(keytype), 0, raw, 4, keytypelen);
            Array.Copy(itobNetwork((int)key.Exponent.Length), 0, raw, 4 + keytypelen, 4);
            Array.Copy(key.Exponent, 0, raw, 4 + keytypelen + 4, key.Exponent.Length);
            Array.Copy(itobNetwork((int)key.Modulus.Length), 0, raw, 4 + keytypelen + 4 + key.Exponent.Length, 4);
            Array.Copy(key.Modulus, 0, raw, 4 + keytypelen + 4 + key.Exponent.Length + 4, key.Modulus.Length);
            return Convert.ToBase64String(raw);
        }

        private static RSAParameters pubkeyFromBase64(string base64)
        {
            // OpenSSL standard of deserializing a public key from BASE64
            byte[] raw = Convert.FromBase64String(base64);
            if (raw.Length < 4 + 3 + 4 + 1 + 4 + 1) throw new ArgumentException("Invalid public key format; size is too small.");

            int keytypelen = btoiNetwork(raw, 0);
            if (keytypelen != 3 && keytypelen != 7) throw new ArgumentException("Invalid public key format; it must be an RSA key stored in OpenSSL format.");

            string keytype = Encoding.ASCII.GetString(raw, 4, keytypelen);
            if (keytype != "rsa" && keytype != "ssh-rsa") throw new ArgumentException("Invalid public key format; key type must be either 'rsa' or 'ssh-rsa'.");

            int explen = btoiNetwork(raw, 4 + keytypelen);
            if (explen > 8192) throw new ArgumentException("Invalid public key format; RSA exponent length too long.");

            int modlen = btoiNetwork(raw, 4 + keytypelen + 4 + explen);
            if (modlen > 8192) throw new ArgumentException("Invalid public key format; RSA modulus length too long.");

            RSAParameters key = new RSAParameters() { Exponent = new byte[explen], Modulus = new byte[modlen] };
            Array.Copy(raw, 4 + keytypelen + 4, key.Exponent, 0, explen);
            Array.Copy(raw, 4 + keytypelen + 4 + explen + 4, key.Modulus, 0, modlen);
            return key;
        }

        private static byte[] signDataWithKey(byte[] toSign, RSAParameters key)
        {
            try
            {
                using (var rsa = new RSACryptoServiceProvider())
                {
                    // Import the given key:
                    rsa.ImportParameters(key);

                    return rsa.SignData(toSign, new SHA1CryptoServiceProvider());
                }
            }
            catch (CryptographicException)
            {
                return null;
            }
        }

        private static bool verifySignedHashWithKey(byte[] toVerify, byte[] signedData, RSAParameters key)
        {
            try
            {
                using (var rsa = new RSACryptoServiceProvider())
                {
                    rsa.ImportParameters(key);

                    return rsa.VerifyData(toVerify, new SHA1CryptoServiceProvider(), signedData);
                }
            }
            catch (CryptographicException)
            {
                return false;
            }
        }

        private static RSAParameters generateKey()
        {
            // Create a new key-pair automatically:
            using (var rsa = new RSACryptoServiceProvider())
            {
                // Export the generated key:
                return rsa.ExportParameters(true);
            }
        }

        #endregion

        #region Logging

        private string LogPath { get { return ctx.Server.MapPath(ctx.Request.AppRelativeCurrentExecutionFilePath + ".log"); } }

        private IEnumerable<string[]> getLogRecords()
        {
            var logfi = new System.IO.FileInfo(LogPath);
            if (!logfi.Exists) yield break;

            string[] lines = System.IO.File.ReadAllLines(LogPath, Encoding.UTF8);
            foreach (string line in lines)
            {
                string[] row = splitTabDelimited(line);
                if (row.Length != 4) continue;

                yield return row;
            }
            yield break;
        }

        [System.Diagnostics.Conditional("LogQueries")]
        private void logQuery(string query, string execURL)
        {
            string hostName = null;
            try
            {
                hostName = System.Net.Dns.GetHostEntry(ctx.Request.UserHostAddress).HostName;

                // If the hostname is not an IP address, remove the trailing domain names to get just the local machine name:
                System.Net.IPAddress addr;
                if (!System.Net.IPAddress.TryParse(hostName, out addr))
                {
                    int dotidx = hostName.IndexOf('.');
                    if (dotidx != -1) hostName = hostName.Remove(dotidx);
                }
            }
            catch (System.Net.Sockets.SocketException) { }

            try
            {
                // Log query to a rolling log file:
                System.IO.File.AppendAllText(
                    LogPath,
                    String.Concat(
                        encodeTabDelimited(DateTimeOffset.Now.ToString()), "\t",
                        encodeTabDelimited(hostName ?? ctx.Request.UserHostAddress ?? String.Empty), "\t",
                        encodeTabDelimited(query), "\t",
                        encodeTabDelimited(execURL),
                        Environment.NewLine
                    ),
                    Encoding.UTF8
                );
            }
            catch
            {
                // Not much to do here. Don't really care to warn the user if it fails.
            }
        }

        #endregion

        public bool IsReusable { get { return false; } }

        private string getFormOrQueryValue(string name)
        {
            return ctx.Request.Form[name] ?? ctx.Request.QueryString[name];
        }

        private string[] getFormOrQueryValues(string name)
        {
            return ctx.Request.Form.GetValues(name) ?? ctx.Request.QueryString.GetValues(name);
        }

        private static string encodeTabDelimited(string value)
        {
            StringBuilder sbResult = new StringBuilder(value.Length * 3 / 2);
            foreach (char ch in value)
            {
                if (ch == '\t') sbResult.Append("\\t");
                else if (ch == '\n') sbResult.Append("\\n");
                else if (ch == '\r') sbResult.Append("\\r");
                else if (ch == '\'') sbResult.Append("\\\'");
                else if (ch == '\"') sbResult.Append("\\\"");
                else if (ch == '\\') sbResult.Append("\\\\");
                else
                {
                    sbResult.Append(ch);
                }
            }
            return sbResult.ToString();
        }

        static string decodeTabDelimited(string value)
        {
            int length = value.Length;
            StringBuilder sbDecoded = new StringBuilder(length);
            for (int i = 0; i < length; ++i)
            {
                char ch = value[i];
                if (ch == '\\')
                {
                    ++i;
                    if (i >= length)
                    {
                        // throw exception?
                        break;
                    }
                    switch (value[i])
                    {
                        case 't': sbDecoded.Append('\t'); break;
                        case 'n': sbDecoded.Append('\n'); break;
                        case 'r': sbDecoded.Append('\r'); break;
                        case '\'': sbDecoded.Append('\''); break;
                        case '\"': sbDecoded.Append('\"'); break;
                        case '\\': sbDecoded.Append('\\'); break;
                        default: break;
                    }
                }
                else sbDecoded.Append(ch);
            }
            return sbDecoded.ToString();
        }

        private static string[] splitTabDelimited(string line)
        {
            string[] cols = line.Split('\t');
            int length = cols.Length;
            string[] result = new string[length];
            for (int i = 0; i < length; ++i)
            {
                // Treat \0 string as null:
                if (cols[i] == "\0") result[i] = null;
                else result[i] = decodeTabDelimited(cols[i]);
            }
            return result;
        }

        private struct ParameterValue
        {
            public readonly string Name;

            public readonly string RawType;
            public readonly System.Data.SqlDbType Type;

            public readonly string RawValue;
            public readonly object SqlValue;

            public readonly bool IsValid;
            public readonly string ValidationMessage;

            public ParameterValue(string name, string type, string value)
            {
                Name = name;
                RawType = type;
                RawValue = value;
                IsValid = true;
                ValidationMessage = null;

                try
                {
                    switch (type)
                    {
                        case "int":
                            Type = System.Data.SqlDbType.Int;
                            SqlValue = new System.Data.SqlTypes.SqlInt32(Int32.Parse(value));
                            break;
                        case "bit":
                            Type = System.Data.SqlDbType.Bit;
                            SqlValue = new System.Data.SqlTypes.SqlBoolean(Boolean.Parse(value));
                            break;
                        case "varchar":
                            Type = System.Data.SqlDbType.VarChar;
                            SqlValue = new System.Data.SqlTypes.SqlString(value);
                            break;
                        case "nvarchar":
                            Type = System.Data.SqlDbType.NVarChar;
                            SqlValue = new System.Data.SqlTypes.SqlString(value);
                            break;
                        case "char":
                            Type = System.Data.SqlDbType.Char;
                            SqlValue = new System.Data.SqlTypes.SqlString(value);
                            break;
                        case "nchar":
                            Type = System.Data.SqlDbType.NChar;
                            SqlValue = new System.Data.SqlTypes.SqlString(value);
                            break;
                        case "datetime":
                            Type = System.Data.SqlDbType.DateTime;
                            SqlValue = new System.Data.SqlTypes.SqlDateTime(DateTime.Parse(value));
                            break;
                        case "datetime2":
                            Type = System.Data.SqlDbType.DateTime2;
                            SqlValue = DateTime.Parse(value);
                            break;
                        case "datetimeoffset":
                            Type = System.Data.SqlDbType.DateTimeOffset;
                            SqlValue = DateTimeOffset.Parse(value);
                            break;
                        case "decimal":
                            Type = System.Data.SqlDbType.Decimal;
                            SqlValue = new System.Data.SqlTypes.SqlDecimal(Decimal.Parse(value));
                            break;
                        case "money":
                            Type = System.Data.SqlDbType.Money;
                            SqlValue = new System.Data.SqlTypes.SqlMoney(Decimal.Parse(value));
                            break;
                        default:
                            Type = System.Data.SqlDbType.VarChar;
                            SqlValue = new System.Data.SqlTypes.SqlString(value);
                            break;
                    }
                }
                catch (Exception ex)
                {
                    IsValid = false;
                    Type = System.Data.SqlDbType.VarChar;
                    SqlValue = null;
                    ValidationMessage = ex.Message;
                }
            }
        }

        private string QuerySQL(
            [QueryParameter("Named connection string")]             string csname,
            [QueryParameter("Custom connection string")]            string cs,

            // CTE is broken out into <identifier> and <expression> parts:
            [QueryParameter("WITH <identifier> AS (expression)")]   string withCTEidentifier,
            [QueryParameter("WITH identifier AS (<expression>)")]   string withCTEexpression,

            // SELECT query is broken out into each clause, all are optional except 'select' itself:
            [QueryParameter("SELECT ...")]                          string select,
            // INTO clause is forbidden
            [QueryParameter("FROM ...")]                            string from,
            [QueryParameter("WHERE ...")]                           string where,
            [QueryParameter("GROUP BY ...")]                        string groupBy,
            [QueryParameter("HAVING ...")]                          string having,
            [QueryParameter("ORDER BY ...")]                        string orderBy,

            ParameterValue[] parameters,

            out string query,
            out string[,] header,
            out long execTimeMsec,
            out IEnumerable<IEnumerable<object>> rows
        )
        {
            query = null;
            header = null;
            execTimeMsec = 0;
            rows = null;

            // Default named connection string:
            csname = csname ?? DefaultConnectionStringName;
            // Use custom connection string if non-null else use the named one:
            string connString = cs ?? System.Configuration.ConfigurationManager.ConnectionStrings[csname].ConnectionString;

            // At minimum, SELECT clause is required:
            if (String.IsNullOrEmpty(select))
            {
                return "SELECT is required";
            }

            // Strip out all SQL comments:
            withCTEidentifier = stripSQLComments(withCTEidentifier);
            withCTEexpression = stripSQLComments(withCTEexpression);
            select = stripSQLComments(select);
            from = stripSQLComments(from);
            where = stripSQLComments(where);
            groupBy = stripSQLComments(groupBy);
            having = stripSQLComments(having);
            orderBy = stripSQLComments(orderBy);

            // Allocate a StringBuilder with enough space to construct the query:
            StringBuilder qb = new StringBuilder(
                (withCTEidentifier ?? "").Length + (withCTEexpression ?? "").Length + ";WITH  AS ()\r\n".Length
              + (select ?? "").Length + "SELECT ".Length
              + (from ?? "").Length + "\r\nFROM ".Length
              + (where ?? "").Length + "\r\nWHERE ".Length
              + (groupBy ?? "").Length + "\r\nGROUP BY ".Length
              + (having ?? "").Length + "\r\nHAVING ".Length
              + (orderBy ?? "").Length + "\r\nORDER BY ".Length
            );

            // Construct the query:
            if (!String.IsNullOrEmpty(withCTEidentifier) && !String.IsNullOrEmpty(withCTEexpression))
                qb.AppendFormat(";WITH {0} AS ({1})\r\n", withCTEidentifier, withCTEexpression);
            qb.AppendFormat("SELECT {0}", select);
            if (!String.IsNullOrEmpty(from)) qb.AppendFormat("\r\nFROM {0}", from);
            if (!String.IsNullOrEmpty(where)) qb.AppendFormat("\r\nWHERE {0}", where);
            if (!String.IsNullOrEmpty(groupBy)) qb.AppendFormat("\r\nGROUP BY {0}", groupBy);
            if (!String.IsNullOrEmpty(having)) qb.AppendFormat("\r\nHAVING {0}", having);
            if (!String.IsNullOrEmpty(orderBy)) qb.AppendFormat("\r\nORDER BY {0}", orderBy);

            // Finalize the query:
            query = qb.ToString();

            // This is a very conservative approach and will lead to false-positives for things like EXISTS() and sub-queries:
            if (containsSQLkeywords(select, "from", "into", "where", "group", "having", "order", "for"))
                return "SELECT clause cannot contain FROM, INTO, WHERE, GROUP BY, HAVING, ORDER BY, or FOR";
            if (containsSQLkeywords(from, "where", "group", "having", "order", "for"))
                return "FROM clause cannot contain WHERE, GROUP BY, HAVING, ORDER BY, or FOR";
            if (containsSQLkeywords(where, "group", "having", "order", "for"))
                return "WHERE clause cannot contain GROUP BY, HAVING, ORDER BY, or FOR";
            if (containsSQLkeywords(groupBy, "having", "order", "for"))
                return "GROUP BY clause cannot contain HAVING, ORDER BY, or FOR";
            if (containsSQLkeywords(having, "order", "for"))
                return "HAVING clause cannot contain ORDER BY or FOR";
            if (containsSQLkeywords(orderBy, "for"))
                return "ORDER BY clause cannot contain FOR";

            // Open a connection and execute the command:
            var conn = new System.Data.SqlClient.SqlConnection(connString);
            var cmd = conn.CreateCommand();

            cmd.CommandText = query;
            cmd.CommandType = System.Data.CommandType.Text;
            cmd.CommandTimeout = 360;   // seconds

            // Add parameters:
            for (int i = 0; i < parameters.Length; ++i)
            {
                if (!parameters[i].IsValid) return String.Format("Parameter '{0}' is invalid: {1}", parameters[i].Name, parameters[i].ValidationMessage);
                cmd.Parameters.Add(parameters[i].Name, parameters[i].Type).SqlValue = parameters[i].SqlValue;
            }

            System.Data.SqlClient.SqlDataReader dr;

            try
            {
                // Open the connection:
                conn.Open();

                // Set the TRANSACTION ISOLATION LEVEL to READ UNCOMMITTED so that we don't block any application queries:
                var tmpcmd = conn.CreateCommand();
                tmpcmd.CommandText = "SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;";
                tmpcmd.ExecuteNonQuery();

                // Set the ROWCOUNT so we don't overload the connection with too many results:
                if (rowLimit > 0)
                {
                    tmpcmd.CommandText = String.Format("SET ROWCOUNT {0};", rowLimit);
                    tmpcmd.ExecuteNonQuery();
                }

                // Time the execution and grab the SqlDataReader:
                System.Diagnostics.Stopwatch swTimer = System.Diagnostics.Stopwatch.StartNew();
                dr = cmd.ExecuteReader(System.Data.CommandBehavior.CloseConnection | System.Data.CommandBehavior.SequentialAccess);
                swTimer.Stop();

                // Record the execution time:
                execTimeMsec = swTimer.ElapsedMilliseconds;
            }
            catch (Exception ex)
            {
                cmd.Dispose();
                conn.Close();
                return ex.Message;
            }

            // Generate the header:
            header = getHeader(dr);
            // Create an enumerator over the results in sequential access order:
            rows = enumerateResults(conn, cmd, dr);

            // No errors:
            return null;
        }

        private static string[,] getHeader(System.Data.SqlClient.SqlDataReader dr)
        {
            // Generate the header:
            int fieldCount = dr.FieldCount;

            var header = new string[fieldCount, 2];
            for (int i = 0; i < fieldCount; ++i)
            {
                header[i, 0] = dr.GetName(i);
                header[i, 1] = formatSQLtype(dr, i);
            }

            return header;
        }

        private static IEnumerable<IEnumerable<object>> enumerateResults(System.Data.SqlClient.SqlConnection conn, System.Data.SqlClient.SqlCommand cmd, System.Data.SqlClient.SqlDataReader dr)
        {
            using (conn)
            using (cmd)
            using (dr)
            {
                int fieldCount = dr.FieldCount;

                object[] values = new object[fieldCount];

                while (dr.Read())
                {
                    yield return enumerateColumns(dr, fieldCount);
                }

                conn.Close();
            }
        }

        private static IEnumerable<object> enumerateColumns(System.Data.SqlClient.SqlDataReader dr, int fieldCount)
        {
            for (int i = 0; i < fieldCount; ++i)
            {
                // TODO: stream using System.Data.IDataRecord
                object col = dr.GetValue(i);
                yield return col;
            }
        }

        private static string formatSQLtype(System.Data.SqlClient.SqlDataReader dr, int ordinal)
        {
            string name = dr.GetDataTypeName(ordinal);
            // NOTE: we won't get the varchar(N) size information in the header.
            return name;
        }

        /// <summary>
        /// Correctly strips out all SQL comments, excluding false-positives from string literals.
        /// </summary>
        /// <param name="s"></param>
        /// <returns></returns>
        private static string stripSQLComments(string s)
        {
            if (s == null) return null;

            StringBuilder sb = new StringBuilder(s.Length);
            int i = 0;
            while (i < s.Length)
            {
                if (s[i] == '\'')
                {
                    // Skip strings.
                    sb.Append('\'');

                    ++i;
                    while (i < s.Length)
                    {
                        if ((i < s.Length - 1) && (s[i] == '\'') && (s[i + 1] == '\''))
                        {
                            // Skip the escaped quote char:
                            sb.Append('\'');
                            sb.Append('\'');
                            i += 2;
                        }
                        else if (s[i] == '\'')
                        {
                            sb.Append('\'');
                            ++i;
                            break;
                        }
                        else
                        {
                            sb.Append(s[i]);
                            ++i;
                        }
                    }
                }
                else if ((i < s.Length - 1) && (s[i] == '-') && (s[i + 1] == '-'))
                {
                    // Scan up to next '\r\n':
                    i += 2;
                    while (i < s.Length)
                    {
                        if ((i < s.Length - 1) && (s[i] == '\r') && (s[i + 1] == '\n'))
                        {
                            // Leave off the parser at the newline:
                            break;
                        }
                        else if ((s[i] == '\r') || (s[i] == '\n'))
                        {
                            // Leave off the parser at the newline:
                            break;
                        }
                        else ++i;
                    }

                    // All of the line comment is now skipped.
                }
                else if ((i < s.Length - 1) && (s[i] == '/') && (s[i + 1] == '*'))
                {
                    // Scan up to next '*/':
                    i += 2;
                    while (i < s.Length)
                    {
                        if ((i < s.Length - 1) && (s[i] == '*') && (s[i + 1] == '/'))
                        {
                            // Skip the end '*/':
                            i += 2;
                            break;
                        }
                        else ++i;
                    }

                    // All of the block comment is now skipped.
                }
                else if (s[i] == ';')
                {
                    // No ';'s allowed.
                    throw new Exception("No semicolons are allowed in any query clause");
                }
                else
                {
                    // Write out the character and advance the pointer:
                    sb.Append(s[i]);
                    ++i;
                }
            }

            return sb.ToString();
        }

        /// <summary>
        /// Checks each word in a SQL fragment against the <paramref name="keywords"/> list and returns true if any match.
        /// </summary>
        /// <param name="s"></param>
        /// <param name="keywords"></param>
        /// <returns></returns>
        private static bool containsSQLkeywords(string s, params string[] keywords)
        {
            if (s == null) return false;

            int rec = 0;
            int i = 0;
            int pdepth = 0;

            while (i < s.Length)
            {
                // Allow letters and underscores to pass for keywords:
                if (Char.IsLetter(s[i]) || s[i] == '_')
                {
                    if (rec == -1) rec = i;

                    ++i;
                    continue;
                }

                // Check last keyword only if at depth 0 of nested parens (this allows subqueries):
                if ((rec != -1) && (pdepth == 0))
                {
                    if (keywords.Contains(s.Substring(rec, i - rec), StringComparer.OrdinalIgnoreCase))
                        return true;
                }

                if (s[i] == '\'')
                {
                    // Process strings.

                    ++i;
                    while (i < s.Length)
                    {
                        if ((i < s.Length - 1) && (s[i] == '\'') && (s[i + 1] == '\''))
                        {
                            // Skip the escaped quote char:
                            i += 2;
                        }
                        else if (s[i] == '\'')
                        {
                            ++i;
                            break;
                        }
                        else ++i;
                    }

                    rec = -1;
                }
                else if ((s[i] == '[') || (s[i] == '"'))
                {
                    // Process quoted identifiers.

                    if (s[i] == '[')
                    {
                        // Bracket quoted identifier.
                        ++i;
                        while (i < s.Length)
                        {
                            if (s[i] == ']')
                            {
                                ++i;
                                break;
                            }
                            else ++i;
                        }
                    }
                    else if (s[i] == '"')
                    {
                        // Double-quoted identifier. Note that these are not strings.
                        ++i;
                        while (i < s.Length)
                        {
                            if ((i < s.Length - 1) && (s[i] == '"') && (s[i + 1] == '"'))
                            {
                                i += 2;
                            }
                            else if (s[i] == '"')
                            {
                                ++i;
                                break;
                            }
                            else ++i;
                        }
                    }

                    rec = -1;
                }
                else if (s[i] == ' ' || s[i] == '.' || s[i] == ',' || s[i] == '\r' || s[i] == '\n')
                {
                    rec = -1;

                    ++i;
                }
                else if (s[i] == '(')
                {
                    rec = -1;

                    ++pdepth;
                    ++i;
                }
                else if (s[i] == ')')
                {
                    rec = -1;

                    --pdepth;
                    if (pdepth < 0)
                    {
                        throw new Exception("Too many closing parentheses encountered");
                    }
                    ++i;
                }
                else if (s[i] == ';')
                {
                    // No ';'s allowed.
                    throw new Exception("No semicolons are allowed in any query clause");
                }
                else
                {
                    // Check last keyword:
                    if (rec != -1)
                    {
                        if (keywords.Contains(s.Substring(rec, i - rec), StringComparer.OrdinalIgnoreCase))
                            return true;
                    }

                    rec = -1;
                    ++i;
                }
            }

            // We must be at paren depth 0 here:
            if (pdepth > 0)
            {
                throw new Exception(String.Format("{0} {1} left unclosed", pdepth, pdepth == 1 ? "parenthesis" : "parentheses"));
            }

            if (rec != -1)
            {
                if (keywords.Contains(s.Substring(rec, i - rec), StringComparer.OrdinalIgnoreCase))
                    return true;
            }
            return false;
        }
    }

    [AttributeUsage(AttributeTargets.Parameter, AllowMultiple = false)]
    public sealed class QueryParameterAttribute : System.Attribute
    {
        public QueryParameterAttribute()
        {
        }

        public QueryParameterAttribute(string description)
        {
            this.Description = description;
        }

        public string Description { get; private set; }
    }
}