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
using System.Web;
using System.Security.Cryptography;

namespace QueryAshx
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

        #region RSA

        private static byte[] itobNetwork(int i)
        {
            return BitConverter.GetBytes(System.Net.IPAddress.HostToNetworkOrder(i));
        }

        private static int btoiNetwork(byte[] b, int startIndex)
        {
            return System.Net.IPAddress.NetworkToHostOrder(BitConverter.ToInt32(b, startIndex));
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

        #region OpenSSL Private Key decryption

        private static bool privkeyFromOpenSSL(string[] lines, Func<string> getPassphrase, out RSAParameters key)
        {
            key = new RSAParameters();
            if (lines[0] != "-----BEGIN RSA PRIVATE KEY-----") return false;

            byte[] iv = null;

            // Parse headers:
            int i;
            for (i = 1; i < lines.Length; ++i)
            {
                if (lines[i].Length == 0)
                {
                    ++i;
                    break;
                }

                int colon = lines[i].IndexOf(':');
                if (colon < 0) break;

                string headerName = lines[i].Substring(0, colon);
                string headerValue = lines[i].Substring(colon + 2);

                if (headerName == "DEK-Info")
                {
                    string[] desparts = headerValue.Split(',');
                    if (desparts[0] != "DES-EDE3-CBC") return false;

                    // Convert hex chars to bytes for the IV:
                    iv = new byte[desparts[1].Length / 2];
                    for (int j = 0, b = 0; j < desparts[1].Length; j += 2, ++b)
                        iv[b] = Convert.ToByte(desparts[1].Substring(j, 2), 16);
                }
            }

            // No data?
            if (i >= lines.Length) return false;

            // Read the rest of the lines into a base64 string:
            int count = lines.Skip(i).Take(lines.Length - i).Sum(l => l.Length);
            StringBuilder b64 = new StringBuilder(count);
            for (; i < lines.Length; ++i)
            {
                if (lines[i] == "-----END RSA PRIVATE KEY-----") break;
                b64.Append(lines[i]);
            }

            byte[] privkeyans1;
            if (iv != null)
            {
                // Prompt for a passphrase and decrypt the private key with it:
                string passphrase = getPassphrase();
                if (String.IsNullOrEmpty(passphrase)) return false;

                byte[] deskey = getOpenSSL3DESkey(iv, passphrase, 1, 2);
                byte[] encdata = Convert.FromBase64String(b64.ToString());
                privkeyans1 = decrypt3DESCBC(encdata, deskey, iv);
            }
            else
            {
                // Just decode the BASE64:
                privkeyans1 = Convert.FromBase64String(b64.ToString());
            }

            if (privkeyans1 == null) return false;
            if (!decodeRSAPrivateKey(privkeyans1, out key)) return false;

            return true;
        }

        public static bool decodeRSAPrivateKey(byte[] privkey, out RSAParameters key)
        {
            MemoryStream input = new MemoryStream(privkey);
            BinaryReader binr = new BinaryReader(input);

            ushort num2 = 0;
            int count = 0;

            try
            {
                num2 = binr.ReadUInt16();
                if (num2 == 33072)
                {
                    binr.ReadByte();
                }
                else if (num2 == 33328)
                {
                    binr.ReadInt16();
                }
                else
                {
                    key = new RSAParameters();
                    return false;
                }
                if (binr.ReadUInt16() != 258)
                {
                    key = new RSAParameters();
                    return false;
                }
                if (binr.ReadByte() != 0)
                {
                    key = new RSAParameters();
                    return false;
                }
                count = getIntegerSize(binr);
                byte[] data = binr.ReadBytes(count);
                count = getIntegerSize(binr);
                byte[] buffer2 = binr.ReadBytes(count);
                count = getIntegerSize(binr);
                byte[] buffer3 = binr.ReadBytes(count);
                count = getIntegerSize(binr);
                byte[] buffer4 = binr.ReadBytes(count);
                count = getIntegerSize(binr);
                byte[] buffer5 = binr.ReadBytes(count);
                count = getIntegerSize(binr);
                byte[] buffer6 = binr.ReadBytes(count);
                count = getIntegerSize(binr);
                byte[] buffer7 = binr.ReadBytes(count);
                count = getIntegerSize(binr);
                byte[] buffer8 = binr.ReadBytes(count);

                key = new RSAParameters
                {
                    Modulus = data,
                    Exponent = buffer2,
                    D = buffer3,
                    P = buffer4,
                    Q = buffer5,
                    DP = buffer6,
                    DQ = buffer7,
                    InverseQ = buffer8
                };

                return true;
            }
            catch (Exception)
            {
                key = new RSAParameters();
                return false;
            }
            finally
            {
                binr.Close();
            }
        }

        private static int getIntegerSize(BinaryReader binr)
        {
            byte num = 0;
            byte num2 = 0;
            byte num3 = 0;
            int num4 = 0;
            if (binr.ReadByte() != 2)
            {
                return 0;
            }
            num = binr.ReadByte();
            if (num == 129)
            {
                num4 = binr.ReadByte();
            }
            else if (num == 130)
            {
                num3 = binr.ReadByte();
                num2 = binr.ReadByte();
                byte[] buffer2 = new byte[4];
                buffer2[0] = num2;
                buffer2[1] = num3;
                byte[] buffer = buffer2;
                num4 = BitConverter.ToInt32(buffer, 0);
            }
            else
            {
                num4 = num;
            }
            while (binr.ReadByte() == 0)
            {
                num4--;
            }
            binr.BaseStream.Seek(-1L, SeekOrigin.Current);
            return num4;
        }

        private static byte[] getOpenSSL3DESkey(byte[] salt, string secpswd, int count, int miter)
        {
            int num = 16;
            byte[] destinationArray = new byte[num * miter];
            byte[] destination = Encoding.ASCII.GetBytes(secpswd);
            byte[] buffer3 = new byte[destination.Length + salt.Length];
            Array.Copy(destination, buffer3, destination.Length);
            Array.Copy(salt, 0, buffer3, destination.Length, salt.Length);
            MD5 md = new MD5CryptoServiceProvider();
            byte[] sourceArray = null;
            byte[] buffer5 = new byte[num + buffer3.Length];
            for (int i = 0; i < miter; i++)
            {
                if (i == 0)
                {
                    sourceArray = buffer3;
                }
                else
                {
                    Array.Copy(sourceArray, buffer5, sourceArray.Length);
                    Array.Copy(buffer3, 0, buffer5, sourceArray.Length, buffer3.Length);
                    sourceArray = buffer5;
                }
                for (int j = 0; j < count; j++)
                {
                    sourceArray = md.ComputeHash(sourceArray);
                }
                Array.Copy(sourceArray, 0, destinationArray, i * num, sourceArray.Length);
            }
            byte[] buffer6 = new byte[24];
            Array.Copy(destinationArray, buffer6, buffer6.Length);
            Array.Clear(destination, 0, destination.Length);
            Array.Clear(buffer3, 0, buffer3.Length);
            Array.Clear(sourceArray, 0, sourceArray.Length);
            Array.Clear(buffer5, 0, buffer5.Length);
            Array.Clear(destinationArray, 0, destinationArray.Length);
            return buffer6;
        }

        private static byte[] decrypt3DESCBC(byte[] cipherData, byte[] desKey, byte[] IV)
        {
            MemoryStream stream = new MemoryStream();
            TripleDES edes = TripleDES.Create();
            edes.Key = desKey;
            edes.IV = IV;

            try
            {
                CryptoStream cs = new CryptoStream(stream, edes.CreateDecryptor(), CryptoStreamMode.Write);
                cs.Write(cipherData, 0, cipherData.Length);
                cs.Close();
            }
            catch (Exception)
            {
                //Debug.WriteLine(exception.Message);
                return null;
            }

            return stream.ToArray();
        }

        #endregion

        #endregion

        #region Private helpers

        private void UIMarshal(Action uiAction)
        {
            if (this.InvokeRequired)
                this.BeginInvoke(uiAction);
            else
                uiAction();
        }

        private static Dictionary<string, object> parseJSON(string json)
        {
            // Deserialize the JSON:
            var jss = new System.Web.Script.Serialization.JavaScriptSerializer();
            jss.RecursionLimit = 8;
            jss.MaxJsonLength = int.MaxValue;
            var dict = jss.Deserialize<Dictionary<string, object>>(json);
            return dict;
        }

        private static string serializeJSON(Dictionary<string, object> values)
        {
            var jss = new System.Web.Script.Serialization.JavaScriptSerializer();
            jss.RecursionLimit = 8;
            jss.MaxJsonLength = int.MaxValue;
            string json = jss.Serialize(values);
            return json;
        }

        private static Dictionary<string, object> parseJSONFile(string jsonPath)
        {
            if (!File.Exists(jsonPath)) return new Dictionary<string, object>();
            return parseJSON(File.ReadAllText(jsonPath));
        }

        private static void serializeJSONFile(string jsonPath, Dictionary<string, object> values)
        {
            string json = serializeJSON(values);
            File.WriteAllText(jsonPath, json, Encoding.UTF8);
        }

        private static Type getCLRTypeForSQLType(string sqlTypeName)
        {
            // TODO: complete me!
            return typeof(string);
        }

        private static void doubleBuffered(DataGridView dgv, bool setting)
        {
            Type dgvType = dgv.GetType();
            PropertyInfo pi = dgvType.GetProperty("DoubleBuffered", BindingFlags.Instance | BindingFlags.NonPublic);
            pi.SetValue(dgv, setting, null);
        }

        private sealed class AsyncUpdateViewState
        {
            public HttpWebRequest req;
            public Action enableQueryPanels;
            public DataGridView dgResults;
            public Action<int> reportQueryTime;
            public Action<Dictionary<string, object>> handleError;
        }

        private void responseCallbackUpdateGridResults(IAsyncResult iar)
        {
            var st = (AsyncUpdateViewState)iar.AsyncState;

            UIMarshal(st.enableQueryPanels);

            // Damn you, HttpWebResponse and your stupid exception handling for non-200 requests.
            HttpWebResponse rsp;
            try
            {
                rsp = (HttpWebResponse)st.req.EndGetResponse(iar);
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
                //Debug.WriteLine(json);
            }

            // Deserialize the JSON:
            var dict = parseJSON(json);
            json = null;

            Dictionary<string, object> errdict;
            if (dict.TryGetValueAs("error", o => (Dictionary<string, object>)o, out errdict))
            {
                // Handle error responses:
                st.handleError(errdict);
                return;
            }

            // Should have a successful result now:
#if false
            foreach (KeyValuePair<string, object> pair in dict)
                Debug.WriteLine(String.Format("rsp.{0} = {1}", pair.Key, pair.Value));
#endif

            ArrayList alHeader, alResults;
            int timeMsec = -1;
            timeMsec = dict.GetValueOrDefaultAs("time", o => (int)o, -1);
            alHeader = dict.GetValueOrDefaultAs("header", o => (ArrayList)o);
            alResults = dict.GetValueOrDefaultAs("results", o => (ArrayList)o);

            var header = (
                from Dictionary<string, object> h in alHeader
                select new
                {
                    name = h.GetValueOrDefaultAs("name", o => (string)o),
                    sqlTypeName = h.GetValueOrDefaultAs("type", o => (string)o),
                    ordinal = h.GetValueOrDefaultAs("ordinal", o => (int)o)
                }
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

            // Now set up the UI on the UI thread:
            UIMarshal(() =>
            {
                st.reportQueryTime(timeMsec);

                var dg = st.dgResults;

                // Set up the grid for usability:
                doubleBuffered(dg, true);
                dg.AlternatingRowsDefaultCellStyle.BackColor = Color.Azure;
                dg.AllowUserToAddRows = false;
                dg.AllowUserToDeleteRows = false;
                dg.AllowUserToOrderColumns = false;
                dg.ClipboardCopyMode = DataGridViewClipboardCopyMode.EnableWithAutoHeaderText;
                dg.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.None;
                dg.AllowUserToResizeColumns = true;
                dg.AllowUserToResizeRows = true;
                dg.ReadOnly = true;
                // Set the grid's data source:
                dg.DataSource = dt;
                // Disable sorting:
                foreach (DataGridViewColumn column in dg.Columns)
                {
                    column.SortMode = DataGridViewColumnSortMode.NotSortable;
                }
            });
        }

        private UriBuilder getBaseURL()
        {
            // Try to parse the base URL:
            try
            {
                UriBuilder reqUrib = new UriBuilder(txtURL.Text);
                return reqUrib;
            }
            catch (Exception)
            {
                msgbox("Please enter a valid URL.");
                return null;
            }
        }

        private static string UrlEncodeParameters(IDictionary<string, string> pairs)
        {
            return String.Join("&", (
                from pair in pairs
                select String.Concat(pair.Key, "=", HttpUtility.UrlEncode(pair.Value))
            ).ToArray());
        }

        private static HttpWebRequest createPOSTRequestFormEncoded(string url, string accept, Dictionary<string, string> postData)
        {
            var req = (HttpWebRequest)HttpWebRequest.Create(url);
            req.Method = "POST";
            req.Accept = accept;
            req.ContentType = "application/x-www-form-urlencoded";

            // This opens a connection to the web site:
            using (var reqstr = req.GetRequestStream())
            using (var tw = new StreamWriter(reqstr))
            {
                bool isFirst = true;
                foreach (KeyValuePair<string, string> pair in postData)
                {
                    if (!isFirst) tw.Write('&'); else isFirst = false;
                    tw.Write("{0}={1}", pair.Key, HttpUtility.UrlEncode(pair.Value));
                }
            }

            return req;
        }

        #endregion

        #region UI actions

        private DialogResult msgbox(string message)
        {
            return MessageBox.Show(this, message, "query.ashx", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        /// <summary>
        /// Executes the SQL query from the "Query" tab and renders the results.
        /// </summary>
        /// <param name="sender"></param>
        /// <param name="e"></param>
        private void btnQueryExecute_Click(object sender, EventArgs e)
        {
            // Try to parse the base URL:
            UriBuilder reqUrib = getBaseURL();
            if (reqUrib == null) return;

            // Construct the query string for the request:
            reqUrib.Query = UrlEncodeParameters(new Dictionary<string, string>
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
            });

            // Create the HTTP GET request to expect application/json:
            HttpWebRequest req = (HttpWebRequest)HttpWebRequest.Create(reqUrib.Uri);
            req.Method = "GET";
            req.Accept = "application/json";

            // Disable reentrancy:
            pnlQuery.Enabled = false;
            btnQueryExecute.Enabled = false;

            var asyncst = new AsyncUpdateViewState()
            {
                req = req,
                enableQueryPanels = () =>
                {
                    pnlQuery.Enabled = true;
                    btnQueryExecute.Enabled = true;
                },
                dgResults = dgQueryResults,
                reportQueryTime = (int msec) =>
                {
                    lblQueryTime.Text = String.Format("Execution time: {0,6} msec", msec);
                },
                handleError = (dict) =>
                {
                    string message = dict.GetValueOrDefaultAs("message", o => (string)o);
                    msgbox(message);
                }
            };

            // Asynchronously fetch the response and display the results to the DataGridView:
            req.BeginGetResponse(new AsyncCallback(responseCallbackUpdateGridResults), (object)asyncst);
        }

        private void btnModifyBrowsePrivateKeyPath_Click(object sender, EventArgs e)
        {
            if (dlgImportKey.ShowDialog() != System.Windows.Forms.DialogResult.OK)
                return;

            txtModifyPrivateKeyPath.Text = dlgImportKey.FileName;
        }

        private void btnModifyCommit_Click(object sender, EventArgs e)
        {
            // Try to parse the base URL:
            UriBuilder reqUrib = getBaseURL();
            if (reqUrib == null) return;

            if (String.IsNullOrEmpty(txtModifyPrivateKeyPath.Text))
            {
                msgbox("An OpenSSL RSA private key file must be specified in order to use this feature.");
                return;
            }

            string privateKeyPath = txtModifyPrivateKeyPath.Text.Trim();
            if (!File.Exists(privateKeyPath))
            {
                msgbox("Could not find the OpenSSL RSA private key file specified.");
                return;
            }

            string cmd = txtModifyCommand.Text.Trim();
            string query = txtModifyQuery.Text.Trim();
            if (String.IsNullOrEmpty(cmd) || String.IsNullOrEmpty(query))
            {
                msgbox("Both a command and a verification query are required.");
                return;
            }

            // Load the lines from the private key file:
            string[] openSSLprivateKey = File.ReadAllLines(privateKeyPath);

            // TODO: add a "1" mode for commit!
            // Have the commit button enable only if this function successfully returns results.
            // Disable the button if anything changes on the form.

            // Construct the query string for the request:
            reqUrib.Query = UrlEncodeParameters(new Dictionary<string, string> { { "mu", "0" } });

            // Decrypt the private key file, prompting for a passphrase if encrypted:
            RSAParameters key;
            if (!privkeyFromOpenSSL(
                openSSLprivateKey,
                () =>
                {
                    if (String.IsNullOrEmpty(txtModifyPassphrase.Text))
                    {
                        msgbox("This private key requires a passphrase. Please provide one.");
                        return null;
                    }
                    return txtModifyPassphrase.Text;
                },
                out key)
            )
            {
                msgbox("Either failed to read private key or passphrase is incorrect!");
                return;
            }

            byte[] data = Encoding.UTF8.GetBytes(cmd + "\n" + query);
            long timestampTicks = DateTime.UtcNow.Ticks;
            byte[] toSign = BitConverter.GetBytes(timestampTicks).Concat(data).ToArray();
            byte[] signed = signDataWithKey(toSign, key);

            // POST to server:
            string pubkey64 = pubkeyToBase64(key);
            string signed64 = Convert.ToBase64String(signed);

            Debug.WriteLine("public-key:\n{0}\n", pubkey64);
            Debug.WriteLine("signed-hash:\n{0}\n", signed64);

            var postData = new Dictionary<string, string>
            {
                { "p", pubkey64 },
                { "s", signed64 },
                { "ts", timestampTicks.ToString() },
                { "c", cmd },
                { "q", query },
                { "cs", txtConnectionString.Text.Trim() }
            };

            var req = createPOSTRequestFormEncoded(reqUrib.Uri.AbsoluteUri, "application/json", postData);

            // Disable reentrancy:
            pnlModifyCommand.Enabled = false;
            pnlModifyQuery.Enabled = false;
            btnModifyCommit.Enabled = false;

            var asyncst = new AsyncUpdateViewState()
            {
                req = req,
                enableQueryPanels = () =>
                {
                    pnlModifyCommand.Enabled = true;
                    pnlModifyQuery.Enabled = true;
                    btnModifyCommit.Enabled = true;
                },
                dgResults = dgModifyResults,
                reportQueryTime = (int msec) =>
                {
                    lblModifyTime.Text = String.Format("Execution time: {0,6} msec", msec);
                },
                handleError = (dict) =>
                {
                    string message = dict.GetValueOrDefaultAs("message", o => (string)o);
                    msgbox(message);
                }
            };

            // Asynchronously fetch the response and display the results to the DataGridView:
            req.BeginGetResponse(new AsyncCallback(responseCallbackUpdateGridResults), (object)asyncst);
        }

        private readonly string recentSettingsPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "recent.json");

        private void GUIClient_Load(object sender, EventArgs e)
        {
            var dict = parseJSONFile(recentSettingsPath);

            // Load recent URLs:
            var urls = dict.GetValueOrDefaultAs("urls", o => (ArrayList)o, () => new ArrayList(0));
            txtURL.Items.Clear();
            txtURL.Items.AddRange((
                from s in urls.OfType<string>()
                where s != null
                let strim = s.Trim()
                where strim.Length > 0
                select strim).ToArray());
            if (urls.Count > 0) txtURL.SelectedIndex = 0;

            // Load recent connection strings:
            var connectionStrings = dict.GetValueOrDefaultAs("cs", o => (ArrayList)o, () => new ArrayList(0));
            txtConnectionString.Items.Clear();
            txtConnectionString.Items.AddRange((
                from s in connectionStrings.OfType<string>()
                where s != null
                let strim = s.Trim()
                where strim.Length > 0
                select strim).ToArray());
            if (connectionStrings.Count > 0) txtConnectionString.SelectedIndex = 0;
        }

        #endregion

        private void persistSettings()
        {
            var dict = new Dictionary<string, object> {
                { "urls", (
                    from s in txtURL.Items.OfType<string>()
                    where s != null
                    let strim = s.Trim()
                    where strim.Length > 0
                    select strim).ToArray() },
                { "cs", (
                    from s in txtConnectionString.Items.OfType<string>()
                    where s != null
                    let strim = s.Trim()
                    where strim.Length > 0
                    select strim).ToArray() }
            };
            serializeJSONFile(recentSettingsPath, dict);
        }

        private void txtURL_Leave(object sender, EventArgs e)
        {
            if (!String.IsNullOrEmpty(txtURL.Text))
            {
                if (!txtURL.Items.OfType<string>().Contains(txtURL.Text, StringComparer.OrdinalIgnoreCase))
                    txtURL.Items.Add(txtURL.Text);
            }
            persistSettings();
        }

        private void txtConnectionString_Leave(object sender, EventArgs e)
        {
            if (!String.IsNullOrEmpty(txtConnectionString.Text))
            {
                if (!txtConnectionString.Items.OfType<string>().Contains(txtConnectionString.Text, StringComparer.OrdinalIgnoreCase))
                    txtConnectionString.Items.Add(txtConnectionString.Text);
            }
            persistSettings();
        }
    }

    internal static class ExtensionMethods
    {
        public static object[] ToArray(this ICollection col)
        {
            object[] arr = new object[col.Count];
            col.CopyTo(arr, 0);
            return arr;
        }

        public static bool TryGetValueAs<TKey, TValue, TResult>(this IDictionary<TKey, TValue> dict, TKey key, Converter<TValue, TResult> convert, out TResult result)
        {
            TValue value;
            if (dict.TryGetValue(key, out value))
            {
                result = convert(value);
                return true;
            }
            result = default(TResult);
            return false;
        }

        public static bool TryGetValueAs<TKey, TValue, TResult>(this IDictionary<TKey, TValue> dict, TKey key, Converter<TValue, TResult> convert, Func<TResult> getDefaultResult, out TResult result)
        {
            TValue value;
            if (dict.TryGetValue(key, out value))
            {
                result = convert(value);
                return true;
            }
            result = getDefaultResult();
            return false;
        }

        public static TResult GetValueOrDefaultAs<TKey, TValue, TResult>(this IDictionary<TKey, TValue> dict, TKey key, Converter<TValue, TResult> convert)
        {
            TValue value;
            if (dict.TryGetValue(key, out value))
            {
                return convert(value);
            }
            return default(TResult);
        }

        public static TResult GetValueOrDefaultAs<TKey, TValue, TResult>(this IDictionary<TKey, TValue> dict, TKey key, Converter<TValue, TResult> convert, TResult defaultValue)
        {
            TValue value;
            if (dict.TryGetValue(key, out value))
            {
                return convert(value);
            }
            return defaultValue;
        }

        public static TResult GetValueOrDefaultAs<TKey, TValue, TResult>(this IDictionary<TKey, TValue> dict, TKey key, Converter<TValue, TResult> convert, Func<TResult> getDefaultValue)
        {
            TValue value;
            if (dict.TryGetValue(key, out value))
            {
                return convert(value);
            }
            return getDefaultValue();
        }
    }
}
