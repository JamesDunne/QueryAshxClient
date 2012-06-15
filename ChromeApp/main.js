$(document).ready(function () {
    var theme = getTheme();
    $('#mainSplitter').jqxSplitter({ theme: theme, width: '100%', height: '100%', panels: [{ size: "20%", max: 800, min: 220 }, { size: "80%" }] });
    $('#querySplitter').jqxSplitter({ theme: theme, width: '100%', height: '100%', orientation: 'horizontal', panels: [{ size: "70%", collapsible: false }, { size: "30%", collapsible: true }] });
    var source = [
        { label: "Servers", expanded: true, items: [
            { label: "Server1", expanded: true, items: [
                { label: "Db1", items: [
                    { label: "Tables" },
                    { label: "Views" },
                ] },
                { label: "Db2", items: [
                    { label: "Tables" },
                    { label: "Views" },
                ] }
            ] },
            { label: "Server2", expanded: true, items: [
                { label: "Db1", items: [
                    { label: "Tables" },
                    { label: "Views" },
                ] }
            ] }
        ] }
    ];
    $('#objectExplorer').jqxTree({ theme: theme, source: source, width: "100%", height: "100%" });
});
