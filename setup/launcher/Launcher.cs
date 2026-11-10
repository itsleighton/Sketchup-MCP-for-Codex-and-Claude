// Setup launcher for the SketchUp MCP connector.
//
// The EXE contains one embedded resource, "Setup.ps1" (setup/claude/Setup.ps1 or
// setup/codex/Setup.ps1). When run, it writes that script to a new temp folder, runs it
// with Windows PowerShell in this console window, waits for it, removes the temp folder,
// and returns the script's exit code. It does not request administrator rights.
//
// Build with setup/launcher/build.ps1.
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;

internal static class Launcher
{
    private static int Main()
    {
        int exitCode = 1;
        string tempDir = Path.Combine(Path.GetTempPath(), "SketchUpMCPSetup-" + Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(tempDir);
            string scriptPath = Path.Combine(tempDir, "Setup.ps1");
            using (Stream resource = Assembly.GetExecutingAssembly().GetManifestResourceStream("Setup.ps1"))
            {
                if (resource == null)
                {
                    throw new InvalidOperationException("Embedded Setup.ps1 is missing from this EXE.");
                }
                using (FileStream file = File.Create(scriptPath))
                {
                    resource.CopyTo(file);
                }
            }

            string powershell = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.System),
                @"WindowsPowerShell\v1.0\powershell.exe");

            ProcessStartInfo info = new ProcessStartInfo(powershell,
                "-NoProfile -ExecutionPolicy Bypass -File \"" + scriptPath + "\"");
            info.UseShellExecute = false;

            using (Process process = Process.Start(info))
            {
                process.WaitForExit();
                exitCode = process.ExitCode;
            }
        }
        catch (Exception ex)
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine("FAILED: " + ex.Message);
            Console.ResetColor();
        }
        finally
        {
            try { Directory.Delete(tempDir, true); } catch { }
        }

        Console.WriteLine();
        Console.WriteLine("Press Enter to close.");
        try { Console.ReadLine(); } catch { }
        return exitCode;
    }
}
