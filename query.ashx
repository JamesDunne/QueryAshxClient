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

// This changes depending on if attached to a debugger, apparently.
//#define DEBUG
#undef DEBUG

// Enable logging of queries to ~/query.ashx.log
#define LogQueries

using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Web;

namespace AdHocQuery
{
    public class AdHocQueryServiceProvider : IHttpHandler
    {
        /// <summary>
        /// Default connection string's name from your web.config &lt;connectionStrings&gt; section.
        /// </summary>
        const string DefaultConnectionStringName = "FIXME";

        private HttpContext ctx;

        public void ProcessRequest(HttpContext ctx)
        {
            this.ctx = ctx;
            HttpRequest req = ctx.Request;
            HttpResponse rsp = ctx.Response;

            try
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

pre
{
	font-size: small;
	margin-left: 1em;
	overflow-x: auto;
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
    clear: left;
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

th.coltype
{
    background-color: #6cc;
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

                bool actionExecute = (String.Equals(req.HttpMethod, "POST", StringComparison.OrdinalIgnoreCase) || String.Equals(getFormOrQueryValue("action"), "Execute", StringComparison.OrdinalIgnoreCase));

                // Dynamically show/hide the rows depending on which FORM values we have provided:
                tw.Write("<style type=\"text/css\">");

                bool displayWITH = !String.IsNullOrEmpty(withCTEidentifier) && !String.IsNullOrEmpty(withCTEexpression);
                bool displayFROM = !String.IsNullOrEmpty(from);
                bool displayWHERE = !String.IsNullOrEmpty(where);
                bool displayGROUPBY = !String.IsNullOrEmpty(groupBy);
                bool displayHAVING = !String.IsNullOrEmpty(having);
                bool displayORDERBY = !String.IsNullOrEmpty(orderBy);
                tw.Write("tr#rowWITH    {{ {0} }}", displayWITH ? String.Empty : "display: none;");
                tw.Write("tr#rowFROM    {{ {0} }}", displayFROM ? String.Empty : "display: none;");
                tw.Write("tr#rowWHERE   {{ {0} }}", displayWHERE ? String.Empty : "display: none;");
                tw.Write("tr#rowGROUPBY {{ {0} }}", displayGROUPBY ? String.Empty : "display: none;");
                tw.Write("tr#rowHAVING  {{ {0} }}", displayHAVING ? String.Empty : "display: none;");
                tw.Write("tr#rowORDERBY {{ {0} }}", displayORDERBY ? String.Empty : "display: none;");

                tw.Write("</style>");

                // Import jQuery 1.6.2:
                tw.Write(@"<script type=""text/javascript"" src=""http://ajax.googleapis.com/ajax/libs/jquery/1.6.2/jquery.min.js""></script>");
                // Import jQueryUI 1.8.5:
                tw.Write(@"<script type=""text/javascript"" src=""http://ajax.googleapis.com/ajax/libs/jqueryui/1.8.5/jquery-ui.min.js""></script>");
                tw.Write(@"<link rel=""stylesheet"" type=""text/css"" href=""http://ajax.googleapis.com/ajax/libs/jqueryui/1.8.5/themes/redmond/jquery-ui.css"" />");

                // Now write out the javascript to allow toggling of show/hide per each query builder row:
                tw.Write(@"<script type=""text/javascript""><!--
$(function() {
    $('#btnWITH')   .click(function() { $('#rowWITH').toggle(); return false; });
    $('#btnFROM')   .click(function() { $('#rowFROM').toggle(); return false; });
    $('#btnWHERE')  .click(function() { $('#rowWHERE').toggle(); return false; });
    $('#btnGROUPBY').click(function() { $('#rowGROUPBY').toggle(); return false; });
    $('#btnHAVING') .click(function() { $('#rowHAVING').toggle(); return false; });
    $('#btnORDERBY').click(function() { $('#rowORDERBY').toggle(); return false; });

    // Enable the tabbed view:
    $('#tabs').tabs();
    $('#tabs').tabs('select', " + (actionExecute ? "1" : "0") + @");

    // Enable buttons:
    $('input:submit, a, button').button();

    var coltypeVisible = true;
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

                tw.Write(@"<style>
.ui-widget .ui-widget {
  font-size: 0.75em;
}
</style>");
                // Start the <body> section:
                tw.Write("</head><body bgcolor='#ffffff' text='#222222' link='#1122cc' vlink='#6611cc' alink='#d14836'>");

                // Create a UriBuilder based on the current request Uri that overrides the query-string:
                UriBuilder execUri = new UriBuilder(req.Url);
                execUri.Query = String.Join("&",
                    req.Form.AllKeys.Union(req.QueryString.AllKeys)
                    .Select(k => HttpUtility.UrlEncode(k) + "=" + HttpUtility.UrlEncode(getFormOrQueryValue(k)))
                    .ToArray()
                );
                string execURL = execUri.Uri.ToString();

                // Create the main form wrapper:
                tw.Write("<div><form method=\"post\" action=\"{0}\">", HttpUtility.HtmlAttributeEncode(req.Url.AbsolutePath));

                // Tabs container:
                tw.Write("<div id='tabs'>");
                tw.Write("<ul>");
                tw.Write("<li><a href='#tab-builder'>Query Builder</a></li>");
                if (actionExecute)
                    tw.Write("<li><a href='#tab-results'>Results</a></li>");
                tw.Write("</ul>");


                // Query-builder tab:
                tw.Write("<div id='tab-builder'><table class='input-table' border='0' cellspacing='0' cellpadding='2'><tbody>");
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
                tw.Write("<tr><td>&nbsp;</td><td><input type='submit' name='action' value='Execute' />");
                // Create a link to share this query with:
                tw.Write("<a href=\"{0}\">link</a>", execURL);
                tw.Write("</td></tr>");
                tw.Write("</tbody></table>");


                // Connection Manager:
                tw.Write("<div id='connections'><table class='input-table' border='0' cellspacing='0' cellpadding='2'><caption>SQL Connection</caption><tbody>");
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
                tw.Write("</tbody></table></div>");


                tw.Write("</div>"); // id='tab-builder'

                // Execution:
                if (actionExecute)
                {
                    string query;
                    string[,] header;
                    IEnumerable<IEnumerable<object>> rows;
                    long execTimeMsec;

                    // Execute the query:
                    string errMessage;
                    try
                    {
                        errMessage = QuerySQL(csname, cs, withCTEidentifier, withCTEexpression, select, from, where, groupBy, having, orderBy, out query, out header, out execTimeMsec, out rows);
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

#if LogQueries
                    try
                    {
                        // Log query to a rolling log file:
                        System.IO.File.AppendAllText(
                            System.IO.Path.Combine(ctx.Server.MapPath("~/"), @"query.ashx.log"),
                            String.Concat(
                                encodeTabDelimited(DateTimeOffset.Now.ToString()), "\t",
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
#endif

                    // Output table:
                    tw.Write("<div id='resultsView'>");
                    tw.Write("<h3>Results</h3>");
                    tw.Write("<div id='resultsInner'>");
                    tw.Write("<div style='float: left;'>");
                    tw.Write("<strong>Last executed:</strong>&nbsp;{1}<br/><strong>Execution time:</strong>&nbsp;{0:N0} ms<br/>", execTimeMsec, DateTimeOffset.Now);
                    tw.Write("</div>");
                    tw.Write("<div style='float: right;'>");
                    tw.Write("<button id='toggleColumnTypeHeaders'>Hide Types</button><br/>");
                    tw.Write("</div>");
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
                                tw.Write("<th class='colname'>{0}</th><th class='coltype'>{1}</th>", HttpUtility.HtmlEncode(header[h, 0]), HttpUtility.HtmlEncode(header[h, 1]));
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
                            bool isNobr = false;
                            string tdclass = null;

                            // Use the SQL type to determine column alignment:
                            string sqltype = header[colnum, 1];
                            if (sqltype == "int" || sqltype == "decimal" || sqltype == "double")
                                align = "right";
                            else if (sqltype == "datetime" || sqltype == "datetimeoffset" || sqltype == "datetime2")
                                isNobr = true;

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
                                    const string hexChars = "0123456789ABCDEF";

                                    StringBuilder sbhex = new StringBuilder(2 + 2 * bytes.Length);
                                    sbhex.Append("0x");
                                    for (int j = 0; j < bytes.Length; ++j)
                                    {
                                        sbhex.Append(hexChars[bytes[j] >> 4]);
                                        sbhex.Append(hexChars[bytes[j] & 0xF]);
                                    }
                                    colvalue = sbhex.ToString();
                                    tdclass = "hexvalue";
                                }
                                else
                                {
                                    // All else, use TypeConverter.ConvertToString:
                                    var tc = System.ComponentModel.TypeDescriptor.GetConverter(ctype);
                                    colvalue = tc.ConvertToString(col);

                                    // Use a <nobr> around short-enough columns that include word-breaking chars.
                                    if ((colvalue.Length <= 60) && !(colvalue.IndexOfAny(new char[] { '\r', '\n' }) >= 0))
                                        isNobr = true;
                                }
                            }

                            string attrs = String.Empty;
                            if (tdclass != null) attrs += " class='" + tdclass + "'";
                            if (align != null) attrs += " style='text-align: " + align + ";'";

                            tw.Write("<td colspan='2'{1}>{2}{0}{3}</td>",
                                HttpUtility.HtmlEncode(colvalue),
                                attrs,
                                isNobr ? "<nobr>" : String.Empty,
                                isNobr ? "</nobr>" : String.Empty
                            );
                        } // foreach (object col in row)

                        tw.Write("</tr>\n");
                    } // foreach (IEnumerable<object> row in rows)
                    tw.Write("</tbody>\n</table>");
                    tw.Write("</div>"); // id='resultsTableDiv'
                    tw.Write("</div></div>");

                end:
                    tw.Write("</div>"); // id='tab-results'
                }

                // End:
                tw.Write("</div>"); // id='tabs'
                tw.Write("</form></div>");
                tw.Write("</body></html>");
            }
            catch (Exception ex)
            {
                rsp.StatusCode = 500;
                rsp.ContentType = "text/html";
                rsp.Write(ex.ToString());
                return;
            }
        }

        public bool IsReusable { get { return false; } }

        private string getFormOrQueryValue(string name)
        {
            return ctx.Request.Form[name] ?? ctx.Request.QueryString[name];
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

        public string QuerySQL(
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

            System.Data.SqlClient.SqlDataReader dr;

            try
            {
                // Open the connection:
                conn.Open();

                // Set the TRANSACTION ISOLATION LEVEL to READ UNCOMMITTED so that we don't block any application queries:
                var tmpcmd = conn.CreateCommand();
                tmpcmd.CommandText = "SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;";
                tmpcmd.ExecuteNonQuery();

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
            int fieldCount = dr.FieldCount;

#if false
            header = new string[fieldCount][];
            for (int i = 0; i < fieldCount; ++i)
            {
                header[i] = new string[2] { dr.GetName(i), formatSQLtype(dr, i) };
            }
#else
            header = new string[fieldCount, 2];
            for (int i = 0; i < fieldCount; ++i)
            {
                header[i, 0] = dr.GetName(i);
                header[i, 1] = formatSQLtype(dr, i);
            }
#endif

            rows = enumerateResults(conn, cmd, dr);

            // No errors:
            return null;
        }

        private IEnumerable<IEnumerable<object>> enumerateResults(System.Data.SqlClient.SqlConnection conn, System.Data.SqlClient.SqlCommand cmd, System.Data.SqlClient.SqlDataReader dr)
        {
            using (conn)
            using (cmd)
            using (dr)
            {
                int fieldCount = dr.FieldCount;

                object[] values = new object[fieldCount];

                while (dr.Read())
                {
#if false
                    int nc = dr.GetValues(values);
                    System.Diagnostics.Debug.Assert(nc == fieldCount);

                    yield return values;
#else
                    yield return enumerateColumns(dr, fieldCount);
#endif
                }

                conn.Close();
            }
        }

        private IEnumerable<object> enumerateColumns(System.Data.SqlClient.SqlDataReader dr, int fieldCount)
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
            while (i < s.Length)
            {
                if (s[i] == '\'')
                {
                    // Check last keyword:
                    if (rec != -1)
                    {
                        if (keywords.Contains(s.Substring(rec, i - rec), StringComparer.OrdinalIgnoreCase))
                            return true;
                    }

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
                    // Check last keyword:
                    if (rec != -1)
                    {
                        if (keywords.Contains(s.Substring(rec, i - rec), StringComparer.OrdinalIgnoreCase))
                            return true;
                    }
                    rec = -1;

                    if (s[i] == '[')
                    {
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
                }
                else if (s[i] == ' ' || s[i] == '(' || s[i] == ')' || s[i] == '.' || s[i] == ',' || s[i] == '\r' || s[i] == '\n')
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
                else if (Char.IsLetter(s[i]) || s[i] == '_')
                {
                    if (rec == -1) rec = i;
                    ++i;
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