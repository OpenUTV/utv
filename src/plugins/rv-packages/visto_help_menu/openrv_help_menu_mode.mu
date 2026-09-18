//
// Copyright (C) 2023  Autodesk, Inc. All Rights Reserved. 
// 
// SPDX-License-Identifier: Apache-2.0 
//
module: openrv_help_menu_mode {
use rvtypes;
use runtime;
use commands;
use app_utils;
use extra_commands;
require system;
require io;
require qt;

documentation: """
UTVHelpMenuMinorMode adds a Help menu and some modal event tables that
implement things like describe key, etc. Help minor mode should always
appear list in the menu bar.
"""
class: UTVHelpMenuMinorMode : MinorMode
{
    \: showManual (void; Event ev, string env)
    {
        require system;
        State state = data();

        try
        {
            let m = system.getenv(env);

            if (runtime.build_os() == "WINDOWS")
            {
                let wpath = regex.replace("/", m, "\\\\");
                system.defaultWindowsOpen(wpath);
            }
            else openUrl("file://" + m);
        }
        catch (...)
        {
            int choice = alertPanel(true,
                                    WarningAlert,
                                    "Manual location unknown",
                                    "Looking for missing env var %s" % env,
                                    "OK", nil, nil);
        }
    }

    \: describeHelp (void; Event ev)
    {
        displayFeedback("Describe Options (Hit 'k' for Keys, 'e' for Events)", 10e6);
        redraw();
        pushEventTable("describe-mode");
    }

    \: describeKeyBinding (void; Event ev)
    {
        redraw();
        displayFeedback("Describe Options -> (Press Any Key For Description) ...", 10e6);
        pushEventTable("describe-mode");
        pushEventTable("describe-key-mode");
    }

    \: docbrowser (void; Event ev)
    {
        State s = data();
        mode_manager.ModeManagerMode mmm = s.modeManager;
        mmm.activateMode("doc_browser", true);
    }

    \: dumpBindings (void; Event ev)
    {
        print("<br><br><hr><center>");
        print("<H1>Current Bindings</H1>");
        print("Modes:");
        for_each (m; activeModes()) print(" %s" % m);

        print("<table border=0><tr><th>Event</th><th>Binding</th></tr>");

        for_each (b; bindings()) 
        {
            let (eventName, description) = b;
            if (description != "") print("<tr><td> %s </td><td> %s </td></tr>" % b);
        }

        print("</table></center><hr>\n");

        showConsole();
    }

    \: commandHelp (void;)
    {
        use autodoc;
        print("<br><br><hr><h1>RV Commands</h1><blockquote>");
        
        for_each (c; document_symbol("commands").split("\n"))
        {
            let l = regex.smatch("commands.([a-zA-Z]+) (.*)", c);
            
            if (l neq nil)
            {
                print("<font face=monospace><b>%s</b> %s</font><br>" % (l[1], l[2]));
            }
        }
        
        print("</blockquote><hr>\n");
        showConsole();
    }

    \:showEnv (void;)
    {
        print ("************ Environment Variables ******************\n");

        let envList = qt.QProcessEnvironment.systemEnvironment().toStringList();
        for_each (var; envList) print ("  %s\n" % var);

        print ("**************** Build Info ************************\n");
        print ("  OS:       %s\n" % runtime.build_os());
        print ("  Arch:     %s\n" % runtime.build_architecture());
        print ("  Compiler: %s\n" % runtime.build_compiler());
        print ("*****************************************************\n");

        showConsole();
    }

    \: opUrl (void; Event ev, string url)
    {
        openUrl (url);
    }


    \: findPythonInterpreter (string;)
    {
        try
        {
            let rv = system.getenv("RV_APP_RV");
            if (rv neq nil && rv != "")
            {
                let base = io.path.basename(rv);
                let dir = rv.substr(0, rv.size() - base.size());
                let pyName = if runtime.build_os() == "WINDOWS" then "py-interp.exe" else "py-interp";
                let p = io.path.join(dir, pyName);
                if (io.path.exists(p)) return p;
            }
        }
        catch (...) { ; }

        if (runtime.build_os() == "WINDOWS")
        {
            try
            {
                let pyhome = system.getenv("PYTHONHOME");
                if (pyhome neq nil && pyhome != "")
                {
                    let p_home = io.path.join(pyhome, "python.exe");
                    if (io.path.exists(p_home)) return p_home;
                    let p_tools = io.path.join(pyhome, "tools/python3/python.exe");
                    if (io.path.exists(p_tools)) return p_tools;
                }

                let depsRoot = system.getenv("OPENUTV_DEPS_ROOT");
                if (depsRoot neq nil && depsRoot != "")
                {
                    let p_deps = io.path.join(depsRoot, "tools/python3/python.exe");
                    if (io.path.exists(p_deps)) return p_deps;
                    let p_deps_py = io.path.join(depsRoot, "python/python.exe");
                    if (io.path.exists(p_deps_py)) return p_deps_py;
                }
            }
            catch (...) { ; }

            return "python.exe";
        }
        else
        {
            let p1 = "/Applications/UTV.app/Contents/MacOS/py-interp";
            if (io.path.exists(p1)) return p1;
            return "python3";
        }
    }

    \: findHelperScript (string; string scriptName)
    {
        try
        {
            let rv = system.getenv("RV_APP_RV");
            if (rv neq nil && rv != "")
            {
                let base = io.path.basename(rv);
                let dir = rv.substr(0, rv.size() - base.size());
                let p_py = io.path.join(dir, scriptName + ".py");
                if (io.path.exists(p_py)) return p_py;
                let p_cmd = io.path.join(dir, scriptName + ".cmd");
                if (io.path.exists(p_cmd)) return p_cmd;
                let p_bat = io.path.join(dir, scriptName + ".bat");
                if (io.path.exists(p_bat)) return p_bat;
                let p = io.path.join(dir, scriptName);
                if (io.path.exists(p)) return p;
                let p_sh = io.path.join(dir, scriptName + ".sh");
                if (io.path.exists(p_sh)) return p_sh;
            }
        }
        catch (...) { ; }

        let p1 = "/Applications/UTV.app/Contents/MacOS/" + scriptName + ".py";
        if (io.path.exists(p1)) return p1;

        let p2 = "/Applications/UTV.app/Contents/Resources/" + scriptName + ".py";
        if (io.path.exists(p2)) return p2;

        let p3 = "/Applications/UTV.app/Contents/MacOS/" + scriptName;
        if (io.path.exists(p3)) return p3;

        let p4 = "/Applications/UTV.app/Contents/Resources/" + scriptName + ".sh";
        if (io.path.exists(p4)) return p4;

        return "";
    }

    \: runHelperScript (void; string scriptPath, string[] extraArgs)
    {
        let isPy = scriptPath.size() > 3 && scriptPath.substr(scriptPath.size() - 3, 3) == ".py";
        if (isPy)
        {
            let py = findPythonInterpreter();
            string[] args = string[] { scriptPath };
            for_each (arg; extraArgs) args.push_back(arg);
            qt.QProcess.startDetached(py, args);
        }
        else if (runtime.build_os() == "WINDOWS")
        {
            string[] args = string[] { "/c", scriptPath };
            for_each (arg; extraArgs) args.push_back(arg);
            qt.QProcess.startDetached("cmd.exe", args);
        }
        else
        {
            string[] args = string[] { scriptPath };
            for_each (arg; extraArgs) args.push_back(arg);
            qt.QProcess.startDetached("/bin/sh", args);
        }
    }

    \: reportIssue (void; Event ev)
    {
        try
        {
            let script = findHelperScript("openutv-diagnostics");
            if (script != "")
            {
                runHelperScript(script, string[] {});
            }
            else
            {
                openUrl("https://github.com/OpenUTV/utv/issues/new?template=bug.yml");
            }
        }
        catch (...)
        {
            openUrl("https://github.com/OpenUTV/utv/issues/new?template=bug.yml");
        }
    }

    \: collectDiagnostics (void; Event ev)
    {
        try
        {
            let script = findHelperScript("openutv-diagnostics");
            if (script != "")
            {
                runHelperScript(script, string[] { "--no-browser" });
            }
            else
            {
                print("WARNING: openutv-diagnostics helper script could not be found.\n");
            }
        }
        catch (...) { ; }
    }

    \: checkUpdates (void; Event ev)
    {
        try
        {
            let script = findHelperScript("openutv-check-updates");
            if (script != "")
            {
                let v = commands.getVersion();
                string curVer = "%d.%d.%d" % (v[0], v[1], v[2]);
                runHelperScript(script, string[] { "--interactive", "--current-version", curVer });
            }
            else
            {
                openUrl("https://github.com/OpenUTV/utv/releases/latest");
            }
        }
        catch (...)
        {
            openUrl("https://github.com/OpenUTV/utv/releases/latest");
        }
    }

    \: inactiveState (int;) { DisabledMenuState; }

    method: UTVHelpMenuMinorMode (UTVHelpMenuMinorMode;)
    {
        Menu menuList = newMenu(MenuItem[] {
                menuText("Online Resources"),
                menuItem("   RV User's Manual", "", "help_category", opUrl(,"https://aswf-openrv.readthedocs.io/en/latest/rv-manuals/rv-user-manual/rv-user-manual-chapter-one.html"), enabledItem),
                menuItem("   RV Reference Manual", "", "help_category", opUrl(,"https://aswf-openrv.readthedocs.io/en/latest/rv-manuals/rv-reference-manual/rv-reference-manual-chapter-one.html"), enabledItem),
                menuItem("   Mu User's Manual", "", "help_category", opUrl(,"https://github.com/OpenUTV/utv/blob/main/docs/rv-manuals/rv-mu-programming.md"), enabledItem),
                menuSeparator(),
                menuItem("   GTO File Format (.rv files)", "", "help_category", opUrl(,"https://github.com/OpenUTV/utv/blob/main/docs/rv-manuals/rv-gto.md"), enabledItem),
                menuSeparator(),
                menuItem("   OpenUTV on GitHub", "", "help_category", opUrl(,"https://github.com/OpenUTV/utv"), enabledItem),
                menuItem("   Report Issue on GitHub...", "", "help_category", reportIssue, enabledItem),
                menuItem("   Check for Updates...", "", "help_category", checkUpdates, enabledItem),
                menuSeparator(),
                menuText("Other Resource"),
                menuItem("   Mu Command API Browser...", "", "help_category", docbrowser, enabledItem),
                menuSeparator(),
                menuText("Utilities"),
                menuItem("   Collect Diagnostics Package...", "", "help_category", collectDiagnostics, enabledItem),
                menuItem("   Describe...", "key-down--?", "help_category", describeHelp, enabledItem),
                menuItem("   Describe Key Binding...", "", "help_category", describeKeyBinding, enabledItem),
                menuItem("   Show Current Bindings", "", "help_category", dumpBindings, enabledItem),
                menuItem("   Show Environment", "", "help_category", ~showEnv, enabledItem)
        });

        Menu menu = newMenu(MenuItem[] {
            subMenu("Help", menuList)
        });

        \: bindDescribe (void; string name, EventFunc F)
        {
            bind("default", "describe-mode", name, F);
        }

        \: bindDescribeRegex (void; string name, EventFunc F)
        {
            bindRegex("default", "describe-mode", name, F);
        }

        \: bindDescribeKey (void; string name, EventFunc F)
        {
            bind("default", "describe-key-mode", name, F);
        }

        \: bindDescribeKeyRegex (void; string name, EventFunc F)
        {
            bindRegex("default", "describe-key-mode", name, F);
        }

        bindDescribeRegex("key-down--shift.*", noop);

        bindDescribe("key-down--k",\: (void; Event ev)
        {
            State state = data();
            displayFeedback("Describe Options -> (Press Any Key For Description) ...", 10e6);
            redraw();
            pushEventTable("describe-key-mode");
        });

        bindDescribe("key-down--e",\: (void; Event ev)
        {
            State state = data();
            displayFeedback("Describe Options -> (Escape Exits, Otherwise Show Event) ...", 10e6);
            redraw();
            pushEventTable("describe-any-event-mode");
        });

        bindDescribeKeyRegex("^key-down.*shift--shift*", noop);
        bindDescribeKeyRegex("^key-down.*alt--alt*", noop);
        bindDescribeKeyRegex("^key-down.*control--control*", noop);
        bindDescribeKeyRegex("^key-down.*meta--meta*", noop);
        bindDescribeKeyRegex("^key-down.*meta--super-left*", noop);
        bindDescribeKeyRegex("^key-down.*meta--super-right*", noop);
        bindDescribeKeyRegex("^key-down.*", \: (void; Event ev)
        {
            State state = data();
            repeat (2) popEventTable();
            let name = ev.name(),
                niceName = name.substr(10, name.size());

            try
            {
                displayFeedback("Key \"%s\" --> %s"
                                % (niceName, bindingDocumentation(ev.name())),
                            5.0);
            }
            catch (...)
            {
                displayFeedback("\"%s\" is Not Bound to Anything" % niceName, 5.0);
            }
            redraw();
        });

        bind("default", "describe-any-event-mode", "key-down--escape", \: (void; Event ev)
        {
            State state = data();
            displayFeedback("Finished Event Feedback Mode");
            repeat (2) popEventTable();
            redraw();
        });

        bindRegex("default", "describe-any-event-mode", "^(key|mod).*", \: (void; Event ev)
        {
            State state = data();
            displayFeedback("Event  \"%s\"    (value = %d) (modifiers = %s)"
                            % (ev.name(), ev.key(), ev.modifiers()), 5.0);
            redraw();
        });

        bindRegex("default", "describe-any-event-mode", "^(pointer|generic|puck|stylus|airbrush|mouse4D|rotating).*",
        \: (void; Event ev)
        {
            State state = data();
            displayFeedback("Event  \"%s\"    (modifiers = %s)"
                            % (ev.name(), ev.modifiers()), 5.0);
            redraw();
        });
        
        this.init("help",
                  [("key-down--?", describeHelp, "Show Help Options")],
                  nil,
                  menu,
                  "z",
                  9999);  // always last
    } 
}

\: createMode (Mode;)
{
    return UTVHelpMenuMinorMode();
}

}
