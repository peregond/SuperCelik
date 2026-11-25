using Xunit;

namespace SerbiaID;

public class LanguagePickerTests
{
    [Fact]
    public void Every_interface_language_names_all_picker_entries()
    {
        var was = Loc.Current;
        try
        {
            foreach (var lang in Enum.GetValues<Lang>())
            {
                Loc.Current = lang;
                var names = Loc.PickerNames();
                Assert.Equal(Loc.PickerOrder.Length, names.Length);
                Assert.All(names, n => Assert.False(string.IsNullOrWhiteSpace(n)));
            }
        }
        finally { Loc.Current = was; }
    }

    [Fact]
    public void Serbian_comes_first_in_both_scripts_then_the_others()
    {
        Assert.Equal(Lang.sr, Loc.PickerOrder[0]);
        Assert.Equal(Lang.srCyrl, Loc.PickerOrder[1]);
        Assert.Equal(2, Loc.PickerTop);
        Assert.Equal(11, Loc.PickerOrder.Distinct().Count());
    }

    [Fact]
    public void Serbian_cyrillic_interface_writes_the_names_in_cyrillic()
    {
        var was = Loc.Current;
        try { Loc.Current = Lang.srCyrl; Assert.Equal("Латиница", Loc.PickerNames()[0]); Assert.Equal("Ћирилица", Loc.PickerNames()[1]); }
        finally { Loc.Current = was; }
    }

    [Fact]
    public void Demo_switch_texts_exist_in_every_language()
    {
        var was = Loc.Current;
        try
        {
            foreach (var lang in Enum.GetValues<Lang>())
            {
                Loc.Current = lang;
                foreach (var key in new[] { "demoCard", "demoHealth", "demoVehicle" })
                    Assert.NotEqual(key, Loc.T(key));
            }
        }
        finally { Loc.Current = was; }
    }
}
