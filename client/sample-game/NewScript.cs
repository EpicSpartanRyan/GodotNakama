using Godot;
using System;
using Backtrace.Model;
using Backtrace;
using Game.Config;

public partial class NewScript : Node2D
{
	private int frame = 0;
    private BacktraceClient _backtraceClient;
	
	// Called when the node enters the scene tree for the first time.
    public override void _Ready()
    {
        var credentials = new BacktraceCredentials(
            Secrets.BacktraceUrl
        );
        _backtraceClient = new BacktraceClient(credentials);
        _backtraceClient.HandleApplicationException();

        try
        {
            throw new InvalidOperationException("Excepción de prueba para verificar la integración de Backtrace en Godot 4.");
        }
        catch (InvalidOperationException exception)
        {
            var report = new BacktraceReport(exception);
            
            var versionInfo = Engine.GetVersionInfo();
            string engineVersion = versionInfo.ContainsKey("string") ? versionInfo["string"].ToString() : "Unknown";
            report.Attributes.Add("godot.version", engineVersion);
            
            _backtraceClient.Send(report);
            
            GD.PrintErr("Excepción de prueba enviada a Backtrace exitosamente.");
        }
    }

	// Called every frame. 'delta' is the elapsed time since the previous frame.
	public override void _Process(double delta)
	{
		frame += 1;
		GD.Print(frame);
	}
}
