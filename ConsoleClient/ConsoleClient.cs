using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.IO;
using System.Net;
using System.Web;

namespace QueryAshx
{
    class Client
    {
        private static void Main(string[] args)
        {
            // Read inputs from files listed on commandline:

            if (args.Length != 3)
            {
                Console.Error.WriteLine("Invalid number of arguments.");
                return;
            }

            // Read OpenSSL private key file:
            string[] openSSLprivateKey = File.ReadAllLines(args[0]);

            // Output JSON file:
            string outputPath = args[2];

            // Modification command file:
            string[] cmdLines = File.ReadAllLines(args[1]);

            var config = readConfig(cmdLines);
            string url = config["url"];

            HttpWebRequest req;
            switch (config["mode"])
            {
                case "MUTATE-TEST":
                case "MUTATE-COMMIT":
                    {
                        bool doCommit = config["mode"] == "MUTATE-COMMIT";
                        string connString = config["connection"];
                        string cmd = config["command"];
                        string query = config["query"];

                        req = doMutate(openSSLprivateKey, url, doCommit, connString, cmd, query);
                        if (req == null) return;
                        break;
                    }
                case "ADD-PUBLICKEY":
                    {
                        string newpubkey64 = cleanBase64(config["new-public-key"]);

                        // Verify that the public key is RSA formatted in OpenSSL:
                        Console.Write("Verifying public key to authorize as RSA...");
                        try
                        {
                            RSAParameters tmp = pubkeyFromBase64(newpubkey64);
                            Console.WriteLine(" verified.");
                        }
                        catch (ArgumentException aex)
                        {
                            Console.WriteLine(" {0}", aex.Message);
                            return;
                        }

                        req = doAddPublicKey(openSSLprivateKey, url, newpubkey64);
                        if (req == null) return;
                        break;
                    }
                case "REVOKE-PUBLICKEY":
                    {
                        string newpubkey64 = cleanBase64(config["revoke-public-key"]);

                        // Verify that the public key is RSA formatted in OpenSSL:
                        Console.Write("Verifying public key to revoke as RSA...");
                        try
                        {
                            RSAParameters tmp = pubkeyFromBase64(newpubkey64);
                            Console.WriteLine(" verified.");
                        }
                        catch (ArgumentException aex)
                        {
                            Console.WriteLine(" {0}", aex.Message);
                            return;
                        }

                        req = doRevokePublicKey(openSSLprivateKey, url, newpubkey64);
                        if (req == null) return;
                        break;
                    }
                default:
                    Console.WriteLine("Unknown operation mode!");
                    return;
            }

            // Get the server's response:
            Console.Write("Submitting request to server...");
            var rsp = getResponse(req);
            Console.WriteLine(" received {0} {1}.", (int)rsp.StatusCode, rsp.StatusDescription);
            Console.WriteLine();

            // Error code:
            if (rsp.StatusCode != HttpStatusCode.OK)
            {
                Console.WriteLine("Error response:");
                using (var rspstr = rsp.GetResponseStream())
                using (var conout = Console.OpenStandardOutput(16384))
                {
                    copyStream(rspstr, conout);
                }
                Console.WriteLine();
                return;
            }

            // Stream the HTTP response to the output file:
            using (var rspstr = rsp.GetResponseStream())
            using (var jsonFile = File.Open(outputPath, FileMode.Create, FileAccess.Write, FileShare.Read))
            {
                Console.WriteLine("Writing response to stdout and '{0}'...", outputPath);
                Console.WriteLine();
                using (var conout = Console.OpenStandardOutput(16384))
                    copyStream(rspstr, jsonFile, conout);
                Console.WriteLine();
                Console.WriteLine();
            }

#if false
            // Server side:
            ///////////////

            // Read `cmd`, `query`, `signed64`, and `pubkey64` from POST data:
            RSAParameters clientpubkey = pubkeyFromBase64(pubkey64);
            data = Encoding.UTF8.GetBytes(cmd + "\n" + query);

            signed = Convert.FromBase64String(signed64);

            if (verifySignedHashWithKey(data, signed, clientpubkey))
                Console.WriteLine("Verified");
            else
                Console.WriteLine("Not Verified");
#endif
        }

        private static HttpWebRequest doAddPublicKey(string[] openSSLprivateKey, string url, string newpubkey64)
        {
            // Decrypt the private key file, prompting for a passphrase if encrypted:
            RSAParameters key;
            if (!privkeyFromOpenSSL(openSSLprivateKey, promptForPassphrase, out key))
            {
                Console.WriteLine("Either failed to read private key or passphrase is incorrect!");
                return null;
            }

            Console.WriteLine("authorize public-key:\n{0}\n", newpubkey64);
            byte[] newpubkey = Convert.FromBase64String(newpubkey64);
            long timestampTicks = DateTime.UtcNow.Ticks;
            byte[] toSign = BitConverter.GetBytes(timestampTicks).Concat(newpubkey).ToArray();
            byte[] signed = signDataWithKey(toSign, key);

            // POST to server:
            string pubkey64 = pubkeyToBase64(key);
            string signed64 = Convert.ToBase64String(signed);

            Console.WriteLine("public-key:\n{0}\n", pubkey64);
            Console.WriteLine("signed-hash:\n{0}\n", signed64);

            var postData = new Dictionary<string, string>
            {
                { "p", pubkey64 },
                { "s", signed64 },
                { "ts", timestampTicks.ToString() },
                { "n", newpubkey64 },
            };

            HttpWebRequest req = createPOSTRequestFormEncoded(
                url + "?ap=1",
                "application/json",
                postData
            );

            return req;
        }

        private static HttpWebRequest doRevokePublicKey(string[] openSSLprivateKey, string url, string newpubkey64)
        {
            // Decrypt the private key file, prompting for a passphrase if encrypted:
            RSAParameters key;
            if (!privkeyFromOpenSSL(openSSLprivateKey, promptForPassphrase, out key))
            {
                Console.WriteLine("Either failed to read private key or passphrase is incorrect!");
                return null;
            }

            Console.WriteLine("revoke public-key:\n{0}\n", newpubkey64);
            byte[] newpubkey = Convert.FromBase64String(newpubkey64);
            long timestampTicks = DateTime.UtcNow.Ticks;
            byte[] toSign = BitConverter.GetBytes(timestampTicks).Concat(newpubkey).ToArray();
            byte[] signed = signDataWithKey(toSign, key);

            // POST to server:
            string pubkey64 = pubkeyToBase64(key);
            string signed64 = Convert.ToBase64String(signed);

            Console.WriteLine("public-key:\n{0}\n", pubkey64);
            Console.WriteLine("signed-hash:\n{0}\n", signed64);

            var postData = new Dictionary<string, string>
            {
                { "p", pubkey64 },
                { "s", signed64 },
                { "ts", timestampTicks.ToString() },
                { "n", newpubkey64 },
            };

            HttpWebRequest req = createPOSTRequestFormEncoded(
                url + "?rp=1",
                "application/json",
                postData
            );

            return req;
        }

        private static HttpWebRequest doMutate(string[] openSSLprivateKey, string url, bool doCommit, string connString, string cmd, string query)
        {
            Console.WriteLine("command:\n{0}\n", cmd);
            Console.WriteLine("query:\n{0}\n", query);
            Console.WriteLine("mode:\n{0}\n", doCommit ? "COMMIT" : "TEST");

            if (doCommit)
            {
                Console.WriteLine("WARNING: You have specified COMMIT mode! This will affect data! Use TEST mode first if you haven't already.");
                Console.Write("Are you sure you want to proceed (Y/N)? ");
                if (Console.ReadLine().Trim().ToLower() != "y")
                {
                    Console.WriteLine("Disabling commit mode.");
                    doCommit = false;
                }
                Console.WriteLine();
            }

            // Decrypt the private key file, prompting for a passphrase if encrypted:
            RSAParameters key;
            if (!privkeyFromOpenSSL(openSSLprivateKey, promptForPassphrase, out key))
            {
                Console.WriteLine("Either failed to read private key or passphrase is incorrect!");
                return null;
            }

            byte[] data = Encoding.UTF8.GetBytes(cmd + "\n" + query);
            long timestampTicks = DateTime.UtcNow.Ticks;
            byte[] toSign = BitConverter.GetBytes(timestampTicks).Concat(data).ToArray();
            byte[] signed = signDataWithKey(toSign, key);

            // POST to server:
            string pubkey64 = pubkeyToBase64(key);
            string signed64 = Convert.ToBase64String(signed);

            Console.WriteLine("public-key:\n{0}\n", pubkey64);
            Console.WriteLine("signed-hash:\n{0}\n", signed64);

            var postData = new Dictionary<string, string>
            {
                { "p", pubkey64 },
                { "s", signed64 },
                { "ts", timestampTicks.ToString() },
                { "c", cmd },
                { "q", query },
                { "cs", connString }
            };

            HttpWebRequest req = createPOSTRequestFormEncoded(
                url + "?mu=" + (doCommit ? "1" : "0"),
                "application/json",
                postData
            );

            return req;
        }

        private static string cleanBase64(string base64)
        {
            // Remove all whitespace:
            return base64.Replace("\n", "").Replace("\r", "").Replace(" ", "").Replace("\t", "").Trim();
        }

        private static string promptForPassphrase()
        {
            // Prompt for the private key passphrase:
            StringBuilder sb = new StringBuilder();
            Console.Write("Enter passphrase for encrypted private key: ");
            ConsoleKeyInfo kb;
            do
            {
                kb = Console.ReadKey(true);

                if (kb.Key == ConsoleKey.Enter) break;
                else if (kb.Key == ConsoleKey.Backspace)
                {
                    if (sb.Length > 0) sb.Remove(sb.Length - 1, 1);
                }
                else
                {
                    sb.Append(kb.KeyChar);
                }
            } while (kb.Key != ConsoleKey.Enter);
            Console.WriteLine();

            string passphrase = sb.ToString();
            return passphrase;
        }

        private static void copyStream(Stream input, params Stream[] outputs)
        {
            const int chunkSize = 16384;
            byte[] chunk = new byte[chunkSize];
            int nr;

            // Stream the HTTP response to the output file:
            while ((nr = input.Read(chunk, 0, chunkSize)) > 0)
            {
                // Multiplex the output:
                for (int i = 0; i < outputs.Length; ++i)
                    outputs[i].Write(chunk, 0, nr);
            }
        }

        private static Dictionary<string, string> readConfig(string[] lines)
        {
            var sections = new Dictionary<string, string>();
            for (int i = 0; i < lines.Length; ++i)
            {
                if (!lines[i].StartsWith(":")) continue;

                string key = lines[i].Substring(1);
                ++i;
                string value = readSection(lines, key, ref i);
                sections.Add(key, value);
            }
            return sections;
        }

        private static string readSection(string[] lines, string name, ref int i)
        {
            string closename = ":!" + name;
            StringBuilder sb = new StringBuilder();
            for (bool first = true; i < lines.Length; ++i, first = false)
            {
                if (lines[i] == closename) break;

                if (!first) sb.Append("\n");
                sb.Append(lines[i]);
            }
            return sb.ToString();
        }

        private static HttpWebRequest createPOSTRequest(string url, string accept)
        {
            var req = (HttpWebRequest)HttpWebRequest.Create(url);
            req.Method = "POST";
            req.Accept = accept;
            return req;
        }

        private static HttpWebRequest createPOSTRequestFormEncoded(string url, string accept, Dictionary<string, string> postData)
        {
            HttpWebRequest req = createPOSTRequest(url, accept);
            req.ContentType = "application/x-www-form-urlencoded";

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

        private static HttpWebResponse getResponse(HttpWebRequest req)
        {
            HttpWebResponse resp;

            // WebExceptions will be thrown on non-200 status responses.
            try
            {
                resp = (HttpWebResponse)req.GetResponse();
            }
            catch (WebException wex)
            {
                // Catch the exception and cast its Response object so we can continue as normal.
                resp = (HttpWebResponse)wex.Response;
            }

            return resp;
        }

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
                byte[] deskey = getOpenSSL3DESkey(iv, passphrase, 1, 2);
                byte[] encdata = Convert.FromBase64String(b64.ToString());
                privkeyans1 = decrypt3DESCBC(encdata, deskey, iv);
            }
            else
            {
                // TODO: verify this!
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
                //Console.WriteLine(exception.Message);
                return null;
            }

            return stream.ToArray();
        }

        #endregion
    }
}
