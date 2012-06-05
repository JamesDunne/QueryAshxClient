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

#define JSONP

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
        public bool IsReusable { get { return true; } }

        public void ProcessRequest(HttpContext ctx)
        {
            // Simulate async processing in sync mode.
            BeginProcessRequest(ctx, new AsyncCallback(EndProcessRequest), null);
        }

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

        public void EndProcessRequest(IAsyncResult asyncResult)
        {
            var rar = (RequestAsyncResult)asyncResult;

            // Handle final output:
            var result = rar.Result;
            var rsp = rar.Context.Response;
            var req = rar.Context.Request;

            if (rar.Exception != null)
                result = formatException(rar.Exception);

            rsp.StatusCode = result.statusCode;

            // JSONP support here:
#if JSONP
            string callback = req.QueryString["callback"];
            if (callback != null)
            {
                // Make sure callback is an identifier:
                if (!isIdentifier(callback))
                {
                    callback = null;
                    result = new JsonResult(400, "Invalid callback query string parameter");
                    goto output;
                }

                // Use javascript content-type and write the callback prefix:
                rsp.ContentType = "application/javascript";
                rsp.Write(callback + "(");
            }
            else
            {
#endif
                // Normal JSON data:
                rsp.ContentType = "application/json";
#if JSONP
            }

        output:
#endif
            // Create a JsonTextWriter to write directly to the HTTP response stream:
            var jrsp = new JsonTextWriter(rsp.Output);

            try
            {
                // Serialize the result object directly to the response stream:
                json.Serialize(jrsp, result);
            }
            catch (Exception ex)
            {
                json.Serialize(jrsp, formatException(ex));
            }

#if JSONP
            // Close the callback expression for JSONP:
            if (callback != null) rsp.Write(");");
#endif
        }

        private static readonly JsonSerializer json = JsonSerializer.Create(new JsonSerializerSettings
        {
            // NOTE(jsd): Include null values in output for clarity.
            NullValueHandling = NullValueHandling.Include,
            ReferenceLoopHandling = ReferenceLoopHandling.Error,
        });

        private static bool isIdentifier(string value)
        {
            if (value == null) return false;
            if (value.Length == 0) return false;

            if ((value[0] != '_') && !Char.IsLetter(value[0])) return false;
            foreach (char c in value)
            {
                if (!Char.IsLetterOrDigit(c) && (c != '_')) return false;
            }

            return true;
        }

        private static JsonResult sqlError(System.Data.SqlClient.SqlException sqex)
        {
            int statusCode = 500;

            var errorData = new List<System.Data.SqlClient.SqlError>(sqex.Errors.Count);
            var msgBuilder = new StringBuilder(sqex.Message.Length);
            foreach (System.Data.SqlClient.SqlError err in sqex.Errors)
            {
                // Skip "The statement has been terminated.":
                if (err.Number == 3621) continue;

                errorData.Add(err);

                if (msgBuilder.Length > 0)
                    msgBuilder.AppendFormat("\n{0}", err.Message);
                else
                    msgBuilder.Append(err.Message);

                // Determine the HTTP status code to return:
                switch (sqex.Number)
                {
                    // Column does not allow NULLs.
                    case 515: statusCode = 400; break;
                    // Violation of UNIQUE KEY constraint '{0}'. Cannot insert duplicate key in object '{1}'.
                    case 2627: statusCode = 409; break;
                }
            }

            string message = msgBuilder.ToString();
            return new JsonResult(statusCode, message, errorData);
        }

        private static JsonResult formatException(Exception ex)
        {
            JsonException jex;
            JsonSerializationException jsex;
            System.Data.SqlClient.SqlException sqex;

            object innerException = null;
            if (ex.InnerException != null)
                innerException = (object)formatException(ex.InnerException);

            if ((jex = ex as JsonException) != null)
            {
                return new JsonResult(jex.StatusCode, jex.Message);
            }
            else if ((jsex = ex as JsonSerializationException) != null)
            {
                object errorData = new
                {
                    type = ex.GetType().FullName,
                    message = ex.Message,
                    stackTrace = ex.StackTrace,
                    innerException
                };

                return new JsonResult(500, jsex.Message, new[] { errorData });
            }
            else if ((sqex = ex as System.Data.SqlClient.SqlException) != null)
            {
                return sqlError(sqex);
            }
            else
            {
                object errorData = new
                {
                    type = ex.GetType().FullName,
                    message = ex.Message,
                    stackTrace = ex.StackTrace,
                    innerException
                };

                return new JsonResult(500, ex.Message, new[] { errorData });
            }
        }
    }

    /// <summary>
    /// An exception to be converted to a JSON error result.
    /// </summary>
    public sealed class JsonException : Exception
    {
        private readonly int _statusCode;
        public JsonException(int statusCode, string message)
            : base(message)
        {
            _statusCode = statusCode;
        }
        public int StatusCode { get { return _statusCode; } }
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

    public sealed class RequestAsyncResult : IAsyncResult
    {
        public object AsyncState { get { return null; } }
        public System.Threading.WaitHandle AsyncWaitHandle { get { return null; } }
        public bool CompletedSynchronously { get; set; }
        public bool IsCompleted { get; set; }

        public HttpContext Context { get; set; }
        public JsonResult Result { get; set; }
        public Exception Exception { get; set; }
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

        private bool completedSynchronously(JsonResult r)
        {
            rar.CompletedSynchronously = true;
            rar.IsCompleted = true;
            rar.Result = r;
            cb(rar);
            return true;
        }

        private bool completedSynchronously(Exception ex)
        {
            rar.CompletedSynchronously = true;
            rar.IsCompleted = true;
            rar.Exception = ex;
            cb(rar);
            return true;
        }

        private bool completedAsynchronously(JsonResult r)
        {
            rar.CompletedSynchronously = false;
            rar.IsCompleted = true;
            rar.Result = r;
            cb(rar);
            return false;
        }

        private bool completedAsynchronously(Exception ex)
        {
            rar.CompletedSynchronously = false;
            rar.IsCompleted = true;
            rar.Exception = ex;
            cb(rar);
            return false;
        }

        public bool Process()
        {
            // Special tool modes:
            if (getFormOrQueryValue("self-update") != null)
            {
                return completedSynchronously(selfUpdate());
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

                JsonOutput outType;
                if (String.Equals(getFormOrQueryValue("o"), "objects", StringComparison.OrdinalIgnoreCase))
                    // JSON with each row a dictionary object { "column_name1": "value1", ... }
                    // Each column name must be unique or the JSON will be invalid.
                    outType = JsonOutput.Dictionary;
                else if (String.Equals(getFormOrQueryValue("o"), "pairs", StringComparison.OrdinalIgnoreCase))
                    // JSON with each row an array of objects [ { "name": "column_name1", "value": "value1" }, ... ]
                    // Each column name does not have to be unique, but produces objects that are more of a hassle to deal with.
                    outType = JsonOutput.KeyValuePair;
                else if (String.Equals(getFormOrQueryValue("o"), "arrays", StringComparison.OrdinalIgnoreCase))
                    // JSON with each row an array of values [ value1, value2, value3, ... ]
                    outType = JsonOutput.Array;
                else
                    outType = JsonOutput.Dictionary;

                return renderJSON(outType, noQuery, noHeader);
            }
            catch (Exception ex)
            {
                return completedSynchronously(ex);
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
                return new JsonResult(500, String.Format("Failed retrieving latest version from github: {0}", ex.Message));
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
                return new JsonResult(500, String.Format("Failed writing latest version to '{0}': {1}", updateAppRelPath, ex.Message));
            }

            newVersion = null;

            // Success:
            return new JsonResult(new { });
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

        private enum JsonOutput
        {
            Dictionary,
            KeyValuePair,
            Array
        }

        private sealed class QueryRequest
        {
            public bool noQuery, noHeader;
            public string csname, cs, withCTEidentifier, withCTEexpression, select, from, where, groupBy, having, orderBy;
            public ParameterValue[] parameters;
        }

        private bool renderJSON(JsonOutput mode, bool noQuery, bool noHeader)
        {
            // Pull FORM values:
            var req = new QueryRequest()
            {
                noQuery = noQuery,
                noHeader = noHeader,
                csname = getFormOrQueryValue("csname"),
                cs = getFormOrQueryValue("cs"),
                withCTEidentifier = getFormOrQueryValue("wi"),
                withCTEexpression = getFormOrQueryValue("we"),
                select = getFormOrQueryValue("select"),
                from = getFormOrQueryValue("from"),
                where = getFormOrQueryValue("where"),
                groupBy = getFormOrQueryValue("groupBy"),
                having = getFormOrQueryValue("having"),
                orderBy = getFormOrQueryValue("orderBy"),
            };

            // Validate and convert parameters:
            ParameterValue[] parameters;
            bool parametersValid = convertParameters(out parameters);
            req.parameters = parameters;

            // Execute the query:
            try
            {
                querySQL(req, completeError, (_1, _2) => completeQuery(_1, _2, mode));
                return false;
            }
            catch (Exception ex)
            {
                return completedSynchronously(ex);
            }
        }

        private void completeError(QueryRequest req, Exception ex)
        {
            completedSynchronously(ex);
        }

        private void completeQuery(QueryRequest req, QueryResult result, JsonOutput mode)
        {
            var final = new Dictionary<string, object>();
            var meta = new Dictionary<string, object>();

            if (!req.noQuery && result.query != null)
            {
                var query_parts = new Dictionary<string, object>();

                if (!String.IsNullOrEmpty(req.withCTEidentifier))
                    query_parts.Add("with_cte_identifier", req.withCTEidentifier);
                if (!String.IsNullOrEmpty(req.withCTEexpression))
                    query_parts.Add("with_cte_expression", req.withCTEexpression);
                query_parts.Add("select", req.select);
                if (!String.IsNullOrEmpty(req.from))
                    query_parts.Add("from", req.from);
                if (!String.IsNullOrEmpty(req.where))
                    query_parts.Add("where", req.where);
                if (!String.IsNullOrEmpty(req.groupBy))
                    query_parts.Add("groupBy", req.groupBy);
                if (!String.IsNullOrEmpty(req.having))
                    query_parts.Add("having", req.having);
                if (!String.IsNullOrEmpty(req.orderBy))
                    query_parts.Add("orderBy", req.orderBy);
                meta.Add("queryParts", query_parts);

                meta.Add("query", result.query);

                // FIXME? value is always a raw string value. This is good for decimal/money types, maybe not so great for everything else.
                meta.Add("parameters", req.parameters.Select(prm => new { name = prm.Name, type = prm.RawType, value = prm.RawValue }).ToArray());
            }

            meta.Add("time", result.execTimeMsec);
            object results = getJSONDictionary(meta, mode, req.noQuery, req.noHeader, result.header, result.rows);

            completedAsynchronously(new JsonResult(results, meta));
        }

        private object getJSONDictionary(Dictionary<string, object> meta, JsonOutput mode, bool noQuery, bool noHeader, string[,] header, IEnumerable<IEnumerable<object>> rows)
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
                meta.Add("header", headers);
            }

            // Convert each result row:
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
                return list;
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
                            result.Add(new Dictionary<string, object> { { "name", header[i, 0] }, { "value", col } });
                        }

                    list.Add(result);
                }
                return list;
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
                            result.Add(col);
                        }

                    list.Add(result);
                }
                return list;
            }
            else
            {
                throw new JsonException(400, "Unknown JSON mode!");
            }
        }

        private string getFormOrQueryValue(string name)
        {
            return ctx.Request.Form[name] ?? ctx.Request.QueryString[name];
        }

        private string[] getFormOrQueryValues(string name)
        {
            return ctx.Request.Form.GetValues(name) ?? ctx.Request.QueryString.GetValues(name);
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

        private sealed class QueryResult
        {
            public string query;
            public string[,] header;
            public long execTimeMsec;
            public IEnumerable<IEnumerable<object>> rows;
        }

        private delegate void errorDelegate(QueryRequest req, Exception ex);
        private delegate void successDelegate(QueryRequest req, QueryResult result);

        private void querySQL(QueryRequest req, errorDelegate err, successDelegate success)
        {
            // Use custom connection string if non-null else use the named one:
            string connString = req.cs;
            if (connString == null && req.csname != null)
                connString = System.Configuration.ConfigurationManager.ConnectionStrings[req.csname].ConnectionString;
            if (connString == null)
                throw new ArgumentException("No connection string supplied");

            // Enable async processing:
            var csb = new System.Data.SqlClient.SqlConnectionStringBuilder(connString);
            csb.AsynchronousProcessing = true;
            csb.ConnectTimeout = 5;
            connString = csb.ToString();

            // At minimum, SELECT clause is required:
            if (String.IsNullOrEmpty(req.select))
            {
                throw new ArgumentException("SELECT is required");
            }

            // Strip out all SQL comments:
            string withCTEidentifier = stripSQLComments(req.withCTEidentifier);
            string withCTEexpression = stripSQLComments(req.withCTEexpression);
            string select = stripSQLComments(req.select);
            string from = stripSQLComments(req.from);
            string where = stripSQLComments(req.where);
            string groupBy = stripSQLComments(req.groupBy);
            string having = stripSQLComments(req.having);
            string orderBy = stripSQLComments(req.orderBy);

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
            string query = qb.ToString();

            // This is a very conservative approach and will lead to false-positives for things like EXISTS() and sub-queries:
            if (containsSQLkeywords(select, "from", "into", "where", "group", "having", "order", "for"))
                throw new ArgumentException("SELECT clause cannot contain FROM, INTO, WHERE, GROUP BY, HAVING, ORDER BY, or FOR");
            if (containsSQLkeywords(from, "where", "group", "having", "order", "for"))
                throw new ArgumentException("FROM clause cannot contain WHERE, GROUP BY, HAVING, ORDER BY, or FOR");
            if (containsSQLkeywords(where, "group", "having", "order", "for"))
                throw new ArgumentException("WHERE clause cannot contain GROUP BY, HAVING, ORDER BY, or FOR");
            if (containsSQLkeywords(groupBy, "having", "order", "for"))
                throw new ArgumentException("GROUP BY clause cannot contain HAVING, ORDER BY, or FOR");
            if (containsSQLkeywords(having, "order", "for"))
                throw new ArgumentException("HAVING clause cannot contain ORDER BY or FOR");
            if (containsSQLkeywords(orderBy, "for"))
                throw new ArgumentException("ORDER BY clause cannot contain FOR");

            // Open a connection and execute the command:
            var conn = new System.Data.SqlClient.SqlConnection(connString);
            var cmd = conn.CreateCommand();

            cmd.CommandText = query;
            cmd.CommandType = System.Data.CommandType.Text;
            cmd.CommandTimeout = 360;   // seconds

            // Add parameters:
            for (int i = 0; i < req.parameters.Length; ++i)
            {
                if (!req.parameters[i].IsValid) throw new ArgumentException(String.Format("Parameter '{0}' is invalid: {1}", req.parameters[i].Name, req.parameters[i].ValidationMessage));
                cmd.Parameters.Add(req.parameters[i].Name, req.parameters[i].Type).SqlValue = req.parameters[i].SqlValue;
            }

            try
            {
                // Open the connection:
                conn.Open();
            }
            catch (Exception ex)
            {
                cmd.Dispose();
                conn.Close();

                err(req, ex);
                return;
            }

            try
            {
                // Set the TRANSACTION ISOLATION LEVEL to READ UNCOMMITTED so that we don't block any application queries:
                var tmpcmd = conn.CreateCommand();
                tmpcmd.CommandText = "SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;";
                tmpcmd.BeginExecuteNonQuery((iar) =>
                {
                    try
                    {
                        ((System.Data.SqlClient.SqlCommand)iar.AsyncState).EndExecuteNonQuery(iar);
                    }
                    catch (Exception ex)
                    {
                        cmd.Dispose();
                        conn.Close();

                        err(req, ex);
                        return;
                    }

                    System.Diagnostics.Stopwatch swTimer = null;
                    AsyncCallback queryComplete = delegate(IAsyncResult iarq)
                    {
                        System.Data.SqlClient.SqlDataReader dr;
                        try
                        {
                            dr = ((System.Data.SqlClient.SqlCommand)iarq.AsyncState).EndExecuteReader(iarq);
                            if (swTimer != null) swTimer.Stop();
                        }
                        catch (Exception ex)
                        {
                            cmd.Dispose();
                            conn.Close();

                            if (swTimer != null) swTimer.Stop();
                            err(req, ex);
                            return;
                        }

                        var result = new QueryResult();
                        result.query = query;
                        result.execTimeMsec = swTimer.ElapsedMilliseconds;
                        // Generate the header:
                        result.header = getHeader(dr);
                        // Create an enumerator over the results in sequential access order:
                        result.rows = enumerateResults(conn, cmd, dr);

                        success(req, result);
                        return;
                    };

                    // Set the ROWCOUNT so we don't overload the connection with too many results:
                    if (rowLimit > 0)
                    {
                        var tmpcmd2 = conn.CreateCommand();
                        tmpcmd2.CommandText = String.Format("SET ROWCOUNT {0};", rowLimit);
                        tmpcmd2.BeginExecuteNonQuery((iar2) =>
                        {
                            try
                            {
                                ((System.Data.SqlClient.SqlCommand)iar2.AsyncState).EndExecuteNonQuery(iar2);
                            }
                            catch (Exception ex)
                            {
                                cmd.Dispose();
                                conn.Close();

                                err(req, ex);
                                return;
                            }

                            try
                            {
                                // Start the query:
                                swTimer = System.Diagnostics.Stopwatch.StartNew();
                                cmd.BeginExecuteReader(queryComplete, cmd, System.Data.CommandBehavior.CloseConnection | System.Data.CommandBehavior.SequentialAccess);
                            }
                            catch (Exception ex)
                            {
                                cmd.Dispose();
                                conn.Close();

                                err(req, ex);
                                return;
                            }
                        }, tmpcmd2);
                    }
                    else
                    {
                        try
                        {
                            // Start the query:
                            swTimer = System.Diagnostics.Stopwatch.StartNew();
                            cmd.BeginExecuteReader(queryComplete, cmd, System.Data.CommandBehavior.CloseConnection | System.Data.CommandBehavior.SequentialAccess);
                        }
                        catch (Exception ex)
                        {
                            cmd.Dispose();
                            conn.Close();

                            err(req, ex);
                            return;
                        }
                    }
                }, tmpcmd);
            }
            catch (Exception ex)
            {
                cmd.Dispose();
                conn.Close();

                err(req, ex);
                return;
            }

            return;
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
}