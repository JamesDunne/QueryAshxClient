namespace rsatest
{
    partial class GUIClient
    {
        /// <summary>
        /// Required designer variable.
        /// </summary>
        private System.ComponentModel.IContainer components = null;

        /// <summary>
        /// Clean up any resources being used.
        /// </summary>
        /// <param name="disposing">true if managed resources should be disposed; otherwise, false.</param>
        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null))
            {
                components.Dispose();
            }
            base.Dispose(disposing);
        }

        #region Windows Form Designer generated code

        /// <summary>
        /// Required method for Designer support - do not modify
        /// the contents of this method with the code editor.
        /// </summary>
        private void InitializeComponent()
        {
            this.groupBox1 = new System.Windows.Forms.GroupBox();
            this.textBox1 = new System.Windows.Forms.TextBox();
            this.label1 = new System.Windows.Forms.Label();
            this.groupBox2 = new System.Windows.Forms.GroupBox();
            this.tabControl1 = new System.Windows.Forms.TabControl();
            this.tbQuery = new System.Windows.Forms.TabPage();
            this.tbModify = new System.Windows.Forms.TabPage();
            this.panel4 = new System.Windows.Forms.Panel();
            this.panel3 = new System.Windows.Forms.Panel();
            this.panel2 = new System.Windows.Forms.Panel();
            this.txtModifyCommand = new System.Windows.Forms.TextBox();
            this.label4 = new System.Windows.Forms.Label();
            this.panel1 = new System.Windows.Forms.Panel();
            this.txtModifyPassphrase = new System.Windows.Forms.TextBox();
            this.label3 = new System.Windows.Forms.Label();
            this.label2 = new System.Windows.Forms.Label();
            this.btnModifyBrowsePrivateKeyPath = new System.Windows.Forms.Button();
            this.txtModifyPrivateKeyPath = new System.Windows.Forms.TextBox();
            this.tbLog = new System.Windows.Forms.TabPage();
            this.label5 = new System.Windows.Forms.Label();
            this.txtModifyQuery = new System.Windows.Forms.TextBox();
            this.label6 = new System.Windows.Forms.Label();
            this.txtConnectionString = new System.Windows.Forms.TextBox();
            this.tbKeys = new System.Windows.Forms.TabPage();
            this.groupBox1.SuspendLayout();
            this.groupBox2.SuspendLayout();
            this.tabControl1.SuspendLayout();
            this.tbModify.SuspendLayout();
            this.panel3.SuspendLayout();
            this.panel2.SuspendLayout();
            this.panel1.SuspendLayout();
            this.SuspendLayout();
            // 
            // groupBox1
            // 
            this.groupBox1.Controls.Add(this.txtConnectionString);
            this.groupBox1.Controls.Add(this.label6);
            this.groupBox1.Controls.Add(this.textBox1);
            this.groupBox1.Controls.Add(this.label1);
            this.groupBox1.Dock = System.Windows.Forms.DockStyle.Top;
            this.groupBox1.Location = new System.Drawing.Point(0, 0);
            this.groupBox1.Name = "groupBox1";
            this.groupBox1.Size = new System.Drawing.Size(695, 81);
            this.groupBox1.TabIndex = 0;
            this.groupBox1.TabStop = false;
            this.groupBox1.Text = "Server";
            // 
            // textBox1
            // 
            this.textBox1.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.textBox1.Location = new System.Drawing.Point(148, 15);
            this.textBox1.Name = "textBox1";
            this.textBox1.Size = new System.Drawing.Size(534, 22);
            this.textBox1.TabIndex = 1;
            // 
            // label1
            // 
            this.label1.AutoSize = true;
            this.label1.Location = new System.Drawing.Point(6, 18);
            this.label1.Name = "label1";
            this.label1.Size = new System.Drawing.Size(129, 17);
            this.label1.TabIndex = 0;
            this.label1.Text = "URL to query.ashx:";
            // 
            // groupBox2
            // 
            this.groupBox2.Controls.Add(this.tabControl1);
            this.groupBox2.Dock = System.Windows.Forms.DockStyle.Fill;
            this.groupBox2.Location = new System.Drawing.Point(0, 81);
            this.groupBox2.Name = "groupBox2";
            this.groupBox2.Size = new System.Drawing.Size(695, 641);
            this.groupBox2.TabIndex = 1;
            this.groupBox2.TabStop = false;
            this.groupBox2.Text = "Operation";
            // 
            // tabControl1
            // 
            this.tabControl1.Controls.Add(this.tbQuery);
            this.tabControl1.Controls.Add(this.tbLog);
            this.tabControl1.Controls.Add(this.tbModify);
            this.tabControl1.Controls.Add(this.tbKeys);
            this.tabControl1.Dock = System.Windows.Forms.DockStyle.Fill;
            this.tabControl1.Location = new System.Drawing.Point(3, 18);
            this.tabControl1.Name = "tabControl1";
            this.tabControl1.SelectedIndex = 0;
            this.tabControl1.Size = new System.Drawing.Size(689, 620);
            this.tabControl1.TabIndex = 0;
            // 
            // tbQuery
            // 
            this.tbQuery.Location = new System.Drawing.Point(4, 25);
            this.tbQuery.Name = "tbQuery";
            this.tbQuery.Padding = new System.Windows.Forms.Padding(3);
            this.tbQuery.Size = new System.Drawing.Size(681, 591);
            this.tbQuery.TabIndex = 0;
            this.tbQuery.Text = "Query";
            this.tbQuery.UseVisualStyleBackColor = true;
            // 
            // tbModify
            // 
            this.tbModify.Controls.Add(this.panel4);
            this.tbModify.Controls.Add(this.panel3);
            this.tbModify.Controls.Add(this.panel2);
            this.tbModify.Controls.Add(this.panel1);
            this.tbModify.Location = new System.Drawing.Point(4, 25);
            this.tbModify.Name = "tbModify";
            this.tbModify.Padding = new System.Windows.Forms.Padding(3);
            this.tbModify.Size = new System.Drawing.Size(681, 591);
            this.tbModify.TabIndex = 1;
            this.tbModify.Text = "Modify";
            this.tbModify.UseVisualStyleBackColor = true;
            // 
            // panel4
            // 
            this.panel4.Dock = System.Windows.Forms.DockStyle.Fill;
            this.panel4.Location = new System.Drawing.Point(3, 242);
            this.panel4.Name = "panel4";
            this.panel4.Size = new System.Drawing.Size(675, 346);
            this.panel4.TabIndex = 6;
            // 
            // panel3
            // 
            this.panel3.Controls.Add(this.txtModifyQuery);
            this.panel3.Controls.Add(this.label5);
            this.panel3.Dock = System.Windows.Forms.DockStyle.Top;
            this.panel3.Location = new System.Drawing.Point(3, 152);
            this.panel3.Name = "panel3";
            this.panel3.Size = new System.Drawing.Size(675, 90);
            this.panel3.TabIndex = 5;
            // 
            // panel2
            // 
            this.panel2.Controls.Add(this.txtModifyCommand);
            this.panel2.Controls.Add(this.label4);
            this.panel2.Dock = System.Windows.Forms.DockStyle.Top;
            this.panel2.Location = new System.Drawing.Point(3, 62);
            this.panel2.Name = "panel2";
            this.panel2.Size = new System.Drawing.Size(675, 90);
            this.panel2.TabIndex = 4;
            // 
            // txtModifyCommand
            // 
            this.txtModifyCommand.AcceptsReturn = true;
            this.txtModifyCommand.AcceptsTab = true;
            this.txtModifyCommand.HideSelection = false;
            this.txtModifyCommand.Location = new System.Drawing.Point(0, 23);
            this.txtModifyCommand.Multiline = true;
            this.txtModifyCommand.Name = "txtModifyCommand";
            this.txtModifyCommand.Size = new System.Drawing.Size(675, 64);
            this.txtModifyCommand.TabIndex = 1;
            // 
            // label4
            // 
            this.label4.AutoSize = true;
            this.label4.Location = new System.Drawing.Point(0, 3);
            this.label4.Name = "label4";
            this.label4.Size = new System.Drawing.Size(105, 17);
            this.label4.TabIndex = 0;
            this.label4.Text = "SQL command:";
            // 
            // panel1
            // 
            this.panel1.Controls.Add(this.txtModifyPassphrase);
            this.panel1.Controls.Add(this.label3);
            this.panel1.Controls.Add(this.label2);
            this.panel1.Controls.Add(this.btnModifyBrowsePrivateKeyPath);
            this.panel1.Controls.Add(this.txtModifyPrivateKeyPath);
            this.panel1.Dock = System.Windows.Forms.DockStyle.Top;
            this.panel1.Location = new System.Drawing.Point(3, 3);
            this.panel1.Name = "panel1";
            this.panel1.Size = new System.Drawing.Size(675, 59);
            this.panel1.TabIndex = 3;
            // 
            // txtModifyPassphrase
            // 
            this.txtModifyPassphrase.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.txtModifyPassphrase.Location = new System.Drawing.Point(208, 31);
            this.txtModifyPassphrase.Name = "txtModifyPassphrase";
            this.txtModifyPassphrase.PasswordChar = '*';
            this.txtModifyPassphrase.Size = new System.Drawing.Size(426, 22);
            this.txtModifyPassphrase.TabIndex = 4;
            // 
            // label3
            // 
            this.label3.AutoSize = true;
            this.label3.Location = new System.Drawing.Point(0, 34);
            this.label3.Name = "label3";
            this.label3.Size = new System.Drawing.Size(87, 17);
            this.label3.TabIndex = 3;
            this.label3.Text = "Passphrase:";
            // 
            // label2
            // 
            this.label2.AutoSize = true;
            this.label2.Location = new System.Drawing.Point(0, 6);
            this.label2.Name = "label2";
            this.label2.Size = new System.Drawing.Size(200, 17);
            this.label2.TabIndex = 0;
            this.label2.Text = "OpenSSL RSA private key file:";
            // 
            // btnModifyBrowsePrivateKeyPath
            // 
            this.btnModifyBrowsePrivateKeyPath.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.btnModifyBrowsePrivateKeyPath.Location = new System.Drawing.Point(641, 3);
            this.btnModifyBrowsePrivateKeyPath.Name = "btnModifyBrowsePrivateKeyPath";
            this.btnModifyBrowsePrivateKeyPath.Size = new System.Drawing.Size(31, 23);
            this.btnModifyBrowsePrivateKeyPath.TabIndex = 2;
            this.btnModifyBrowsePrivateKeyPath.Text = "...";
            this.btnModifyBrowsePrivateKeyPath.UseVisualStyleBackColor = true;
            // 
            // txtModifyPrivateKeyPath
            // 
            this.txtModifyPrivateKeyPath.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.txtModifyPrivateKeyPath.Location = new System.Drawing.Point(208, 3);
            this.txtModifyPrivateKeyPath.Name = "txtModifyPrivateKeyPath";
            this.txtModifyPrivateKeyPath.Size = new System.Drawing.Size(425, 22);
            this.txtModifyPrivateKeyPath.TabIndex = 1;
            // 
            // tbLog
            // 
            this.tbLog.Location = new System.Drawing.Point(4, 25);
            this.tbLog.Name = "tbLog";
            this.tbLog.Padding = new System.Windows.Forms.Padding(3);
            this.tbLog.Size = new System.Drawing.Size(681, 591);
            this.tbLog.TabIndex = 2;
            this.tbLog.Text = "Log";
            this.tbLog.UseVisualStyleBackColor = true;
            // 
            // label5
            // 
            this.label5.AutoSize = true;
            this.label5.Location = new System.Drawing.Point(0, 3);
            this.label5.Name = "label5";
            this.label5.Size = new System.Drawing.Size(152, 17);
            this.label5.TabIndex = 1;
            this.label5.Text = "SQL verification query:";
            // 
            // txtModifyQuery
            // 
            this.txtModifyQuery.AcceptsReturn = true;
            this.txtModifyQuery.AcceptsTab = true;
            this.txtModifyQuery.HideSelection = false;
            this.txtModifyQuery.Location = new System.Drawing.Point(0, 23);
            this.txtModifyQuery.Multiline = true;
            this.txtModifyQuery.Name = "txtModifyQuery";
            this.txtModifyQuery.Size = new System.Drawing.Size(675, 64);
            this.txtModifyQuery.TabIndex = 2;
            // 
            // label6
            // 
            this.label6.AutoSize = true;
            this.label6.Location = new System.Drawing.Point(6, 46);
            this.label6.Name = "label6";
            this.label6.Size = new System.Drawing.Size(120, 17);
            this.label6.TabIndex = 2;
            this.label6.Text = "Connection String";
            // 
            // txtConnectionString
            // 
            this.txtConnectionString.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.txtConnectionString.Location = new System.Drawing.Point(148, 43);
            this.txtConnectionString.Name = "txtConnectionString";
            this.txtConnectionString.Size = new System.Drawing.Size(534, 22);
            this.txtConnectionString.TabIndex = 3;
            // 
            // tbKeys
            // 
            this.tbKeys.Location = new System.Drawing.Point(4, 25);
            this.tbKeys.Name = "tbKeys";
            this.tbKeys.Padding = new System.Windows.Forms.Padding(3);
            this.tbKeys.Size = new System.Drawing.Size(681, 591);
            this.tbKeys.TabIndex = 3;
            this.tbKeys.Text = "Key Management";
            this.tbKeys.UseVisualStyleBackColor = true;
            // 
            // GUIClient
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(8F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(695, 722);
            this.Controls.Add(this.groupBox2);
            this.Controls.Add(this.groupBox1);
            this.Name = "GUIClient";
            this.Text = "query.ashx client";
            this.groupBox1.ResumeLayout(false);
            this.groupBox1.PerformLayout();
            this.groupBox2.ResumeLayout(false);
            this.tabControl1.ResumeLayout(false);
            this.tbModify.ResumeLayout(false);
            this.panel3.ResumeLayout(false);
            this.panel3.PerformLayout();
            this.panel2.ResumeLayout(false);
            this.panel2.PerformLayout();
            this.panel1.ResumeLayout(false);
            this.panel1.PerformLayout();
            this.ResumeLayout(false);

        }

        #endregion

        private System.Windows.Forms.GroupBox groupBox1;
        private System.Windows.Forms.GroupBox groupBox2;
        private System.Windows.Forms.TextBox textBox1;
        private System.Windows.Forms.Label label1;
        private System.Windows.Forms.TabControl tabControl1;
        private System.Windows.Forms.TabPage tbQuery;
        private System.Windows.Forms.TabPage tbModify;
        private System.Windows.Forms.TabPage tbLog;
        private System.Windows.Forms.Button btnModifyBrowsePrivateKeyPath;
        private System.Windows.Forms.TextBox txtModifyPrivateKeyPath;
        private System.Windows.Forms.Label label2;
        private System.Windows.Forms.Panel panel1;
        private System.Windows.Forms.TextBox txtModifyPassphrase;
        private System.Windows.Forms.Label label3;
        private System.Windows.Forms.Panel panel2;
        private System.Windows.Forms.TextBox txtModifyCommand;
        private System.Windows.Forms.Label label4;
        private System.Windows.Forms.Panel panel4;
        private System.Windows.Forms.Panel panel3;
        private System.Windows.Forms.TextBox txtModifyQuery;
        private System.Windows.Forms.Label label5;
        private System.Windows.Forms.TextBox txtConnectionString;
        private System.Windows.Forms.Label label6;
        private System.Windows.Forms.TabPage tbKeys;
    }
}