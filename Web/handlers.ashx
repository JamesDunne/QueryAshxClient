<%@ WebHandler Language="C#" Class="ManagementTools.HandlersManagementHandler" %>
<%@ Assembly Name="System.Core, Version=3.5.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089" %>
<%@ Assembly Name="System.Data, Version=2.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089" %>
<%@ Assembly Name="System.Runtime.Serialization, Version=3.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089" %>
<%@ Assembly Name="System.Xml, Version=2.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089" %>

using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Web;
using System.Xml.Serialization;

namespace ManagementTools
{
    public sealed class HandlersManagementHandler : IHttpHandler
    {
        public bool IsReusable
        {
            get { return true; }
        }

        public void ProcessRequest(HttpContext context)
        {
            new RequestHandler(context).Process();
        }

        private sealed class RequestHandler
        {
            private readonly HttpContext ctx;
            private readonly HttpRequest req;
            private readonly HttpResponse rsp;

            public RequestHandler(HttpContext ctx)
            {
                this.ctx = ctx;
                this.req = ctx.Request;
                this.rsp = ctx.Response;
            }

            public void Process()
            {
                if (String.Equals(req.HttpMethod, "GET", StringComparison.OrdinalIgnoreCase))
                    HandleGET();
                else if (String.Equals(req.HttpMethod, "POST", StringComparison.OrdinalIgnoreCase))
                    HandlePOST();
            }

            public void HandleGET()
            {
                rsp.ContentType = "text/html";
                rsp.Output.WriteLine(
@"<!DOCTYPE html>
<html>
<head>
    <title>Handlers</title>

    <script type=""text/javascript"">
      function fileSelected() {
        var file = document.getElementById('fileToUpload').files[0];
        if (file) {
          var fileSize = 0;
          if (file.size > 1024 * 1024)
            fileSize = (Math.round(file.size * 100 / (1024 * 1024)) / 100).toString() + 'MB';
          else
            fileSize = (Math.round(file.size * 100 / 1024) / 100).toString() + 'KB';

          document.getElementById('fileName').innerHTML = 'Name: ' + file.name;
          document.getElementById('fileSize').innerHTML = 'Size: ' + fileSize;
          document.getElementById('fileType').innerHTML = 'Type: ' + file.type;
        }
      }

      function uploadFile() {
        var fd = new FormData(document.getElementById('form1'));

        var xhr = new XMLHttpRequest();
        xhr.upload.addEventListener(""progress"", uploadProgress, false);
        xhr.addEventListener(""load"", uploadComplete, false);
        xhr.addEventListener(""error"", uploadFailed, false);
        xhr.addEventListener(""abort"", uploadCanceled, false);
        xhr.open(""POST"", """ + req.Url.AbsolutePath + @""");
        xhr.send(fd);
      }

      function uploadProgress(evt) {
        if (evt.lengthComputable) {
          var percentComplete = Math.round(evt.loaded * 100 / evt.total);
          document.getElementById('progressNumber').innerHTML = percentComplete.toString() + '%';
        }
        else {
          document.getElementById('progressNumber').innerHTML = 'unable to compute';
        }
      }

      function uploadComplete(evt) {
        alert(evt.target.responseText);
      }

      function uploadFailed(evt) {
        alert(""There was an error attempting to upload the file."");
      }

      function uploadCanceled(evt) {
        alert(""The upload has been canceled by the user or the browser dropped the connection."");
      }
    </script>
</head>
<body>
  <form id=""form1"" enctype=""multipart/form-data"" method=""post"">
    <div class=""row"">
      <label for=""fileToUpload"">Select a File to Upload</label><br />
      <input type=""file"" name=""fileToUpload"" id=""fileToUpload"" onchange=""fileSelected();""/>
    </div>
    <div class=""row"">
      <label for=""password"">Password:</label>&nbsp;<input type=""password"" name=""password"" />
    </div>
    <div id=""fileName""></div>
    <div id=""fileSize""></div>
    <div id=""fileType""></div>
    <div class=""row"">
      <input type=""button"" onclick=""uploadFile()"" value=""Upload"" />
    </div>
    <div id=""progressNumber""></div>
  </form>
</body>
</html>");
            }
            
            public void HandlePOST()
            {
                // NOTE(jsd): You try implementing digest auth or OAuth in an ashx complete with file upload ability.
                if (req.Form["password"] != "khec123$")
                {
                    rsp.StatusCode = 401;
                    rsp.ContentType = "text/plain";
                    rsp.StatusDescription = "Unauthorized";
                    rsp.Output.WriteLine("Unauthorized");
                    return;
                }

                if (req.Files.Count == 0)
                {
                    return;
                }

                string absPath = ctx.Server.MapPath(req.AppRelativeCurrentExecutionFilePath);
                string uploadDirectory = new System.IO.FileInfo(absPath).DirectoryName;

                rsp.ContentType = "text/plain";

                // Save all uploaded files to the current directory:
                for (int i = 0; i < req.Files.Count; ++i)
                {
                    var file = req.Files[i];

                    // Filter out non .ashx files:
                    string ext = System.IO.Path.GetExtension(file.FileName);
                    if (ext == null || !String.Equals(ext, ".ashx", StringComparison.OrdinalIgnoreCase))
                    {
                        rsp.Output.WriteLine("Rejecting '{0}'", file.FileName);
                        continue;
                    }

                    string fileName = System.IO.Path.GetFileName(file.FileName);
                    string uploadPath = System.IO.Path.Combine(uploadDirectory, fileName);

                    rsp.Output.WriteLine("Accepting '{0}'", fileName);
                    try
                    {
                        file.SaveAs(uploadPath);
                    }
                    catch (Exception ex)
                    {
                        rsp.Output.WriteLine("Failed writing '{0}': '{1}'", fileName, ex.Message);
                    }
                }
            }
        }
    }
}