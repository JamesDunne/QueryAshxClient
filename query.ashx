<%@ WebHandler Language="C#" Class="AdHocQuery.AdHocQueryServiceProvider" %>
<%@ Assembly Name="System.Core, Version=3.5.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089" %>
<%@ Assembly Name="System.Data, Version=2.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089" %>
<%@ Assembly Name="System.Runtime.Serialization, Version=3.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089" %>
<%@ Assembly Name="System.Xml, Version=2.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089" %>

// SQL Query Builder/Executor web tool
// Designed and implemented by James S. Dunne (github.com/JamesDunne)
// on 2011-10-13

// This file was sourced from gist.github.com/

// This changes depending on if attached to a debugger, apparently.
//#define DEBUG
#undef DEBUG

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

                // Head:
                rsp.Output.Write("<!doctype html><html><head><meta http-equiv=\"content-type\" content=\"text/html; charset=UTF-8\"><title>SQL Query Builder</title>");
                rsp.Output.Write(@"<style type=""text/css"">
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
	margin-bottom: 0.25em;
}

.exception
{
	font-weight: bold;
	font-size: small;
    margin-left: 2em;
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
	margin-left: 2em;
	overflow-x: auto;
}

.input-table
{
	font-family: Tahoma, Segoe UI, Arial;
	font-size: small;
	margin-left: 2em;
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
	background-color: #ee9;
}

.input-table>tbody>tr:nth-child(odd)
{
	background-color: #eef;
}

div#resultsView
{
    display: block;
	margin-top: 1em;
}

div#resultsInner
{
	margin-left: 2em;
    max-width: 1280;
    max-height: 32em;
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
    background-color: #cff;
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
    background-color: #880;
}

#footer
{
    padding-top: 2em;
    font-family: Tahoma, Arial;
	font-weight: normal;
	font-size: small;
}
</style>");
                rsp.Output.Write("</head><body bgcolor=#ffffff text=#222222 link=#1122cc vlink=#6611cc alink=#d14836>");

                string csname, cs, withCTEidentifier, withCTEexpression, select, from, where, groupBy, having, orderBy;

                // Pull FORM values:
                csname  = req.Form["csname"];
                cs      = req.Form["cs"];
                withCTEidentifier = req.Form["withCTEidentifier"];
                withCTEexpression = req.Form["withCTEexpression"];
                select  = req.Form["select"];
                from    = req.Form["from"];
                where   = req.Form["where"];
                groupBy = req.Form["groupBy"];
                having  = req.Form["having"];
                orderBy = req.Form["orderBy"];

                // Query builder form:
                rsp.Output.Write("<div><form method=\"post\">");
                rsp.Output.Write("<div><table class='input-table' border='0' cellspacing='0' cellpadding='2'><caption>SQL Connection</caption><tbody>");
                rsp.Output.Write("<tr><td>Named connection string:</td><td><input type='text' name='csname' size='40' value='{0}' /></td>", HttpUtility.HtmlAttributeEncode(csname ?? ""));
                rsp.Output.Write("<tr><td>Custom connection string:</td><td><input type='text' name='cs' size='110' value='{0}' /></td>", HttpUtility.HtmlAttributeEncode(cs ?? ""));
                rsp.Output.Write("</tbody></table></div>");
                rsp.Output.Write("<div><table class='input-table' border='0' cellspacing='0' cellpadding='2'><caption>Query Builder</caption><tbody>");
                rsp.Output.Write("<tr><td class='monospaced sqlkeyword'>WITH</td><td style='vertical-align: middle'><input type='text' name='withCTEidentifier' size='12' value='{0}'/> <span class='monospaced sqlkeyword'>AS</span> (<textarea name='withCTEexpression' cols='78' rows='{2}' style='vertical-align: middle;'>{1}</textarea>)</td>",
                    HttpUtility.HtmlAttributeEncode(withCTEidentifier ?? ""),
                    HttpUtility.HtmlEncode(withCTEexpression),
                    (withCTEexpression ?? "").Count(ch => ch == '\n') + 2
                );
                rsp.Output.Write("<tr><td class='monospaced sqlkeyword'>SELECT</td><td><textarea name='select' cols='100' rows='{1}'>{0}</textarea></td>", HttpUtility.HtmlEncode(select ?? ""), (select ?? "").Count(ch => ch == '\n') + 2);
                rsp.Output.Write("<tr><td class='monospaced sqlkeyword'>FROM</td><td><textarea name='from' cols='100' rows='{1}'>{0}</textarea></td>", HttpUtility.HtmlEncode(from ?? ""), (from ?? "").Count(ch => ch == '\n') + 2);
                rsp.Output.Write("<tr><td class='monospaced sqlkeyword'>WHERE</td><td><textarea name='where' cols='100' rows='{1}'>{0}</textarea></td>", HttpUtility.HtmlEncode(where ?? ""), (where ?? "").Count(ch => ch == '\n') + 2);
                rsp.Output.Write("<tr><td class='monospaced sqlkeyword'>GROUP BY</td><td><textarea name='groupBy' cols='100' rows='{1}'>{0}</textarea></td>", HttpUtility.HtmlEncode(groupBy ?? ""), (groupBy ?? "").Count(ch => ch == '\n') + 1);
                rsp.Output.Write("<tr><td class='monospaced sqlkeyword'>HAVING</td><td><textarea name='having' cols='100' rows='{1}'>{0}</textarea></td>", HttpUtility.HtmlEncode(having ?? ""), (having ?? "").Count(ch => ch == '\n') + 1);
                rsp.Output.Write("<tr><td class='monospaced sqlkeyword'>ORDER BY</td><td><textarea name='orderBy' cols='100' rows='{1}'>{0}</textarea></td>", HttpUtility.HtmlEncode(orderBy ?? ""), (orderBy ?? "").Count(ch => ch == '\n') + 1);
                rsp.Output.Write("<tr><td>&nbsp;</td><td><input type='submit' name='action' value='Execute' /></td>");
                rsp.Output.Write("</tbody></table></div>");
                rsp.Output.Write("</form></div>");

                if (String.Equals(req.HttpMethod, "POST", StringComparison.OrdinalIgnoreCase))
                {
                    string query;
                    string[] header;
                    IEnumerable<object[]> rows;
                    long execTimeMsec;

                    // Execute the query:
                    string errMessage = QuerySQL(csname, cs, withCTEidentifier, withCTEexpression, select, from, where, groupBy, having, orderBy, out query, out header, out execTimeMsec, out rows);

                    if (query != null)
                    {
                        rsp.Output.Write("<div id='query'><h3>Query</h3><pre>{0}</pre></div>", HttpUtility.HtmlEncode(query));
                    }

                    if (errMessage != null)
                    {
                        rsp.Output.Write("<div id='resultsView'><h3>Error</h3><div id='resultsInner'><span class='exception'>{0}</span></div></div>", HttpUtility.HtmlEncode(errMessage));
                        goto end;
                    }

                    // Output table:
                    rsp.Output.Write("<div id='resultsView'><h3>Results</h3><div id='resultsInner'><strong>Execution time:</strong>&nbsp;{0:N0} ms", execTimeMsec);
                    rsp.Output.Write("<table id='resultsTable' border='1' cellspacing='0' cellpadding='2'><thead><tr><th>Row</th>");
                    foreach (string hr in header)
                    {
                        rsp.Output.Write("<th>{0}</th>", HttpUtility.HtmlEncode(hr));
                    }
                    rsp.Output.Write("</tr></thead><tbody>");

                    int rowNumber = 1;
                    foreach (object[] row in rows)
                    {
                        rsp.Output.Write("<tr>");
                        rsp.Output.Write("<td class='rn'>{0}</td>", rowNumber++);
                        
                        for (int i = 0; i < row.Length; ++i)
                        {
                            string tdclass = null;
                            string col;
                            if ((row[i] == null) || (row[i] == DBNull.Value))
                            {
                                // Display NULL value:
                                col = "NULL";
                                tdclass = "nullvalue";
                            }
                            else
                            {
                                // Check type of the vaue:
                                Type ctype = row[i].GetType();
                                if (ctype == typeof(byte[]))
                                {
                                    // Display byte[] as 0xHEXCHARS:
                                    byte[] bytes = (byte[])row[i];
                                    const string hexChars = "0123456789ABCDEF";
                                    
                                    StringBuilder sbhex = new StringBuilder(2 + 2 * bytes.Length);
                                    sbhex.Append("0x");
                                    for (int j = 0; j < bytes.Length; ++j)
                                    {
                                        sbhex.Append(hexChars[bytes[j] >> 4]);
                                        sbhex.Append(hexChars[bytes[j] & 0xF]);
                                    }
                                    col = sbhex.ToString();
                                    tdclass = "hexvalue";
                                }
                                else
                                {
                                    // All else, use TypeConverter.ConvertToString:
                                    var tc = System.ComponentModel.TypeDescriptor.GetConverter(ctype);
                                    col = tc.ConvertToString(row[i]);
                                }
                            }

                            rsp.Output.Write("<td{1}>{0}</td>", HttpUtility.HtmlEncode(col), tdclass == null ? String.Empty : " class='" + tdclass + "'");
                        } // for (int i = 0; i < row.Length; ++i)

                        rsp.Output.Write("</tr>");
                    } // foreach (object[] row in rows)
                    rsp.Output.Write("</tbody></table></div></div>");
                }

                // End:
            end:
                rsp.Output.Write("</body></html>");
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
            out string[] header,
            out long execTimeMsec,
            out IEnumerable<object[]> rows
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
                conn.Open();
                System.Diagnostics.Stopwatch swTimer = System.Diagnostics.Stopwatch.StartNew();
                dr = cmd.ExecuteReader(System.Data.CommandBehavior.CloseConnection | System.Data.CommandBehavior.SequentialAccess);
                swTimer.Stop();
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

            header = new string[fieldCount];
            for (int i = 0; i < fieldCount; ++i)
            {
                header[i] = String.Format("[{0}] {1}", dr.GetName(i), formatSQLtype(dr, i));
            }

            rows = enumerateResults(conn, cmd, dr);

            // No errors:
            return null;
        }

        private IEnumerable<object[]> enumerateResults(System.Data.SqlClient.SqlConnection conn, System.Data.SqlClient.SqlCommand cmd, System.Data.SqlClient.SqlDataReader dr)
        {
            using (conn)
            using (cmd)
            using (dr)
            {
                int fieldCount = dr.FieldCount;

                object[] values = new object[fieldCount];

                while (dr.Read())
                {
                    int nc = dr.GetValues(values);
                    System.Diagnostics.Debug.Assert(nc == fieldCount);

                    yield return values;
                }

                conn.Close();
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
                            if ((i < s.Length - 1) && (s[i] == '"') && (s[i+1] == '"'))
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