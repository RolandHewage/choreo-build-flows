using Newtonsoft.Json;
var obj = new { message = "NuGet proxy flow works via pack build!" };
Console.WriteLine(JsonConvert.SerializeObject(obj));
