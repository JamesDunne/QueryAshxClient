using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Drawing;
using System.Linq;
using System.Text;
using System.Windows.Forms;
using System.Net;
using System.IO;
using System.Diagnostics;
using System.Collections;
using System.Reflection;

namespace rsatest
{
    public partial class GUIClient : Form
    {
        [STAThread]
        static void Main()
        {
            Application.Run(new GUIClient());
        }

        public GUIClient()
        {
            InitializeComponent();
        }

        private void UIMarshal(Action uiAction)
        {
            if (this.InvokeRequired)
                this.BeginInvoke(uiAction);
            else
                uiAction();
        }

        /// <summary>
        /// Executes the SQL query from the "Query" tab and renders the results.
        /// </summary>
        /// <param name="sender"></param>
        /// <param name="e"></param>
        private void btnQueryExecute_Click(object sender, EventArgs e)
        {
            // Try to parse the base URL:
            UriBuilder reqUrib;
            try
            {
                reqUrib = new UriBuilder(txtURL.Text);
            }
            catch (Exception)
            {
                MessageBox.Show("Please enter a valid URL.");
                return;
            }

            // Construct the query string for the request:
            reqUrib.Query = String.Join("&", (
                from pair in new Dictionary<string, string>
                {
                    { "output", "json3" },  // JSON where each row is an array of column values
                    { "no_query", "1" },    // Don't report query back
                    { "cs", txtConnectionString.Text.Trim() },
                    { "wi", txtQueryWithIdentifier.Text.Trim() },
                    { "we", txtQueryWithExpression.Text.Trim() },
                    { "select", txtQuerySelect.Text.Trim() },
                    { "from", txtQueryFrom.Text.Trim() },
                    { "where", txtQueryWhere.Text.Trim() },
                    { "groupBy", txtQueryGroupBy.Text.Trim() },
                    { "having", txtQueryHaving.Text.Trim() },
                    { "orderBy", txtQueryOrderBy.Text.Trim() }
                }
                select String.Concat(pair.Key, "=", pair.Value)
            ).ToArray());

            // Create the HTTP GET request to expect application/json:
            HttpWebRequest req = (HttpWebRequest)HttpWebRequest.Create(reqUrib.Uri);
            req.Method = "GET";
            req.Accept = "application/json";

            // Disable reentrancy:
            pnlQuery.Enabled = false;
            btnQueryExecute.Enabled = false;

            // Asynchronously fetch the response:
            req.BeginGetResponse((AsyncCallback)((IAsyncResult iar) =>
            {
                UIMarshal(() =>
                {
                    pnlQuery.Enabled = true;
                    btnQueryExecute.Enabled = true;
                });

                // Damn you, HttpWebResponse and your stupid exception handling for non-200 requests.
                HttpWebResponse rsp;
                try
                {
                    rsp = (HttpWebResponse)req.EndGetResponse(iar);
                }
                catch (WebException wex)
                {
                    rsp = (HttpWebResponse)wex.Response;
                }

                // Read the response as JSON:
                string json;
                using (var rspstr = rsp.GetResponseStream())
                using (var tr = new StreamReader(rspstr, Encoding.UTF8))
                {
                    json = tr.ReadToEnd();
                    Debug.WriteLine(json);
                }

                // Deserialize the JSON:
                var jss = new System.Web.Script.Serialization.JavaScriptSerializer();
                jss.RecursionLimit = 4;
                jss.MaxJsonLength = int.MaxValue;
                var dict = jss.Deserialize<Dictionary<string, object>>(json);
                json = null;

                object errObj;
                if (dict.TryGetValue("error", out errObj))
                {
                    // Handle error responses:
                    var errdict = (Dictionary<string, object>)errObj;
                    foreach (KeyValuePair<string, object> pair in errdict)
                        Debug.WriteLine(String.Format("error.{0} = {1}", pair.Key, pair.Value));
                    errObj = null;
                    return;
                }

                // Should have a successful result now:
#if DEBUG
                foreach (KeyValuePair<string, object> pair in dict)
                    Debug.WriteLine(String.Format("rsp.{0} = {1}", pair.Key, pair.Value));
#endif

                ArrayList alHeader, alResults;
                int timeMsec = (int)dict["time"];
                alHeader = (ArrayList)dict["header"];
                alResults = (ArrayList)dict["results"];

                var header = (
                    from Dictionary<string, object> h in alHeader
                    select new { name = (string)h["name"], sqlTypeName = (string)h["type"], ordinal = (int)h["ordinal"] }
                ).ToArray();

                // Create a DataTable to represent the results:
                DataTable dt = new DataTable();
                var columns = (
                    from h in header
                    orderby h.ordinal ascending
                    select new DataColumn(h.name, getCLRTypeForSQLType(h.sqlTypeName))
                ).ToArray();
                dt.Columns.AddRange(columns);
                foreach (ArrayList row in alResults)
                    dt.Rows.Add(row.ToArray());

                UIMarshal(() =>
                {
                    var dg = dgQueryResults;

                    // Set the grid's data source:
                    doubleBuffered(dg, true);
                    dg.AllowUserToAddRows = false;
                    dg.AllowUserToDeleteRows = false;
                    dg.AllowUserToOrderColumns = false;
                    dg.ClipboardCopyMode = DataGridViewClipboardCopyMode.EnableWithAutoHeaderText;
                    dg.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.None;
                    dg.AllowUserToResizeColumns = true;
                    dg.AllowUserToResizeRows = true;
                    dg.ReadOnly = true;
                    dg.DataSource = dt;
                    // Disable sorting:
                    foreach (DataGridViewColumn column in dg.Columns)
                    {
                        column.SortMode = DataGridViewColumnSortMode.NotSortable;
                    }
                });
            }), null);
        }

        private static Type getCLRTypeForSQLType(string sqlTypeName)
        {
            return typeof(string);
        }

        private static void doubleBuffered(DataGridView dgv, bool setting)
        {
            Type dgvType = dgv.GetType();
            PropertyInfo pi = dgvType.GetProperty("DoubleBuffered", BindingFlags.Instance | BindingFlags.NonPublic);
            pi.SetValue(dgv, setting, null);
        }
    }
}
