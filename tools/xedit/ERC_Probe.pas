// Minimal probe: proves the xEdit harness can load a plugin and run a script at
// all, so a timeout can be blamed on the script instead of the environment.
unit UserScript;

var
  sl: TStringList;

function Initialize: integer;
var
  i: integer;
  f: IInterface;
begin
  sl := TStringList.Create;
  sl.Add('probe start');
  sl.SaveToFile('C:\Users\Billy\EldenRingCombat\build\probe.txt');

  f := nil;
  for i := 0 to FileCount - 1 do
    if GetFileName(FileByIndex(i)) = 'EldenRingCombat.esp' then begin
      f := FileByIndex(i);
      Break;
    end;

  if Assigned(f) then
    sl.Add('loaded ' + GetFileName(f) + ' masters=' + IntToStr(MasterCount(f)))
  else
    sl.Add('not loaded');
  sl.Add('files=' + IntToStr(FileCount));
  sl.SaveToFile('C:\Users\Billy\EldenRingCombat\build\probe.txt');

  sl.Free;
  sl := TStringList.Create;
  sl.Add('done');
  sl.SaveToFile('C:\Users\Billy\EldenRingCombat\build\probe.done');
  sl.Free;

  Result := 1;
end;

end.
