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

namespace rsatest
{
    public partial class GUIClient : Form
    {
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

                using (var rspstr = rsp.GetResponseStream())
                using (var tr = new StreamReader(rspstr, Encoding.UTF8))
                {
                    string line;
                    while ((line = tr.ReadLine()) != null)
                        Debug.WriteLine(line);
                }
            }), null);
        }
    }
}
