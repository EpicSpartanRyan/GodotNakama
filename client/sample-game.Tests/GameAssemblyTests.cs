using Godot;
using SampleGame.src.game;

namespace SampleGame.Tests;

public class GameAssemblyTests
{
    [Fact]
    public void MainSceneScriptIsAGodotNode2D()
    {
        Assert.True(typeof(Node2D).IsAssignableFrom(typeof(NewScript)));
    }
}
