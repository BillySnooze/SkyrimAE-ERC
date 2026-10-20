{
  ERC_DumpQuest.pas
  Dumps the element tree of vanilla quests that have a player alias carrying a
  Papyrus script. Used to learn the exact xEdit element paths before generating
  EldenRingCombat.esp, rather than guessing at the QUST layout.
}
unit UserScript;

var
  sl: TStringList;
  shown: integer;

procedure DumpElem(e: IInterface; indent: string);
var
  i: integer;
  v: string;
begin
  if not Assigned(e) then begin
    sl.Add(indent + '<nil>');
    Exit;
  end;
  v := '';
  try
    if ElementCount(e) = 0 then
      v := ' = ' + GetEditValue(e);
  except
    v := ' = <err>';
  end;
  sl.Add(indent + Name(e) + v);
  for i := 0 to ElementCount(e) - 1 do
    DumpElem(ElementByIndex(e, i), indent + '    ');
end;

function Initialize: integer;
var
  f, grp, rec, aliases, al, vmad, scripts, sc, alfr: IInterface;
  i, j, k: integer;
  isPlayer, hasScript: boolean;
begin
  sl := TStringList.Create;
  shown := 0;

  f := FileByLoadOrder(0);
  grp := GroupBySignature(f, 'QUST');
  if not Assigned(grp) then begin
    sl.Add('no QUST group');
    sl.SaveToFile('C:\Users\Billy\EldenRingCombat\build\quest-dump.txt');
    sl.Free;
    Result := 1;
    Exit;
  end;

  sl.Add('QUST records: ' + IntToStr(ElementCount(grp)));

  for i := 0 to ElementCount(grp) - 1 do begin
    if shown >= 2 then Break;
    rec := ElementByIndex(grp, i);
    if Signature(rec) <> 'QUST' then Continue;

    aliases := ElementByName(rec, 'Aliases');
    if not Assigned(aliases) then Continue;

    for j := 0 to ElementCount(aliases) - 1 do begin
      al := ElementByIndex(aliases, j);
      alfr := ElementByName(al, 'ALFR - Forced Reference');
      vmad := ElementByName(al, 'VMAD - Virtual Machine Adapter');
      if not Assigned(vmad) then
        vmad := ElementByName(al, 'VMAD');

      isPlayer := Assigned(alfr) and (Pos('00000014', GetEditValue(alfr)) > 0);
      hasScript := Assigned(vmad);
      if not (isPlayer and hasScript) then Continue;

      Inc(shown);
      sl.Add('');
      sl.Add('===== ' + Name(rec) + ' (alias ' + IntToStr(j) + ') =====');
      DumpElem(rec, '');
      Break;
    end;
  end;

  sl.Add('');
  sl.Add('dumped=' + IntToStr(shown));
  sl.SaveToFile('C:\Users\Billy\EldenRingCombat\build\quest-dump.txt');
  sl.Free;

  // sentinel: tells run-xedit.ps1 the work is done (xEdit may not -autoexit)
  sl := TStringList.Create;
  sl.Add('done');
  sl.SaveToFile('C:\Users\Billy\EldenRingCombat\build\quest-dump.done');
  sl.Free;

  AddMessage('dump done, quests=' + IntToStr(shown));
  Result := 1;
end;

end.
