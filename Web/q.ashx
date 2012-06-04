<%@ WebHandler Language="C#" Class="AdHocQuery.QueryDataServiceProvider" %>
<%@ Assembly Name="System.Core, Version=3.5.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089" %>
<%@ Assembly Name="System.Data, Version=2.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089" %>
<%@ Assembly Name="System.Runtime.Serialization, Version=3.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089" %>
<%@ Assembly Name="System.Xml, Version=2.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089" %>

// SQL Query Executor
// Designed and implemented by James S. Dunne (github.com/JamesDunne)
// on 2012-06-04

// TODO: add optional TOP(N) clause

// Enable logging of queries to ~/q.ashx.log
#define LogQueries

using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Web;
using Newtonsoft.Json;
using Newtonsoft.Json.Serialization;

namespace AdHocQuery
{
    public class QueryDataServiceProvider : IHttpAsyncHandler
    {
        public IAsyncResult BeginProcessRequest(HttpContext context, AsyncCallback cb, object extraData)
        {
            var rar = new RequestAsyncResult()
            {
                Context = context,
                CompletedSynchronously = false,
                IsCompleted = false
            };

            // Create an async request processor:
            var rqp = new QueryDataAsyncProcessor(rar, cb);
            // Process will call cb() when complete:
            rqp.Process();

            return rar;
        }

        public void EndProcessRequest(IAsyncResult result)
        {
            var rar = (RequestAsyncResult)result;

            // Handle final output:
            var rsp = rar.Context.Response;
            if (rar.Exception != null)
            {
                // TODO!!
                rsp.StatusCode = 500;
                //rsp.Output.Write();
                return;
            }
            
            // TODO!!
        }

        public bool IsReusable { get { return true; } }

        public void ProcessRequest(HttpContext ctx)
        {
            // Simulate async processing in sync mode.
            BeginProcessRequest(ctx, new AsyncCallback(EndProcessRequest), null);
        }
    }

    private sealed class RequestAsyncResult : IAsyncResult
    {
        public object AsyncState { get { return null; } }
        public System.Threading.WaitHandle AsyncWaitHandle { get { return null; } }
        public bool CompletedSynchronously { get; set; }
        public bool IsCompleted { get; set; }

        public HttpContext Context { get; set; }
        public JsonResult Result { get; set; }
        public Exception Exception { get; set; }
    }

    public sealed class JsonResultMeta
    {
        [JsonProperty(NullValueHandling = NullValueHandling.Ignore)]
        public bool? committed;
        public long execMsec;
        public DateTimeOffset executed;
        public string server;
        public string database;
    }

    public struct JsonResult
    {
        [JsonIgnore]
        public readonly int statusCode;

        // NOTE(jsd): Fields are serialized to JSON in lexical definition order.
        public readonly bool success;
        [JsonProperty(NullValueHandling = NullValueHandling.Ignore)]
        public readonly string message;
        [JsonProperty(NullValueHandling = NullValueHandling.Ignore)]
        public readonly object errors;
        [JsonProperty(NullValueHandling = NullValueHandling.Ignore)]
        public readonly object meta;

        // NOTE(jsd): `results` must be last.
        [JsonProperty(NullValueHandling = NullValueHandling.Ignore)]
        public readonly object results;

        public JsonResult(int statusCode, string failureMessage)
        {
            this.statusCode = statusCode;
            success = false;
            message = failureMessage;
            errors = null;
            results = null;
            meta = null;
        }

        public JsonResult(int statusCode, string failureMessage, object errorData)
        {
            this.statusCode = statusCode;
            success = false;
            message = failureMessage;
            errors = errorData;
            results = null;
            meta = null;
        }

        public JsonResult(object successfulResults)
        {
            statusCode = 200;
            success = true;
            message = null;
            errors = null;
            results = successfulResults;
            meta = null;
        }

        public JsonResult(object successfulResults, object metaData)
        {
            statusCode = 200;
            success = true;
            message = null;
            errors = null;
            results = successfulResults;
            meta = metaData;
        }
    }

    public sealed class QueryDataAsyncProcessor
    {
        /// <summary>
        /// URL of the latest version to use for self-update feature.
        /// </summary>
        const string LatestVersionURL = "https://raw.github.com/JamesDunne/QueryAshxClient/master/Web/q.ashx";

        /// <summary>
        /// SET ROWCOUNT limit for queries.
        /// </summary>
        const int defaultRowLimit = 1000;

        private int rowLimit = defaultRowLimit;

        private readonly RequestAsyncResult rar;
        private readonly AsyncCallback cb;

        private readonly HttpContext ctx;
        private readonly HttpRequest req;
        private readonly HttpResponse rsp;

        public QueryDataAsyncProcessor(RequestAsyncResult rar, AsyncCallback cb)
        {
            this.rar = rar;
            this.cb = cb;

            this.ctx = rar.Context;
            this.req = ctx.Request;
            this.rsp = ctx.Response;
        }

        private void completedSynchronously(JsonResult r)
        {
            rar.CompletedSynchronously = true;
            rar.IsCompleted = true;
            rar.Result = r;
            cb(rar);
        }

        private void completedSynchronously(Exception ex)
        {
            rar.CompletedSynchronously = true;
            rar.IsCompleted = true;
            rar.Exception = ex;
            cb(rar);
        }

        public void Process()
        {
            // Special tool modes:
            if (getFormOrQueryValue("self-update") != null)
            {
                completedSynchronously(selfUpdate());
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
                else
                {
                }
            }
            catch (Exception ex)
            {
                completedSynchronously(ex);
                return;
            }
        }

        private JsonResult selfUpdate()
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