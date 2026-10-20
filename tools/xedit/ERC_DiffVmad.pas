// ============================================================================
//  ERC_DiffVmad.pas
//  Dumps the VMAD subtree of the generated quest next to a vanilla quest that
//  has the same minimal shape (no quest scripts, one alias script) so any
//  difference in interpretation is obvious.
// ============================================================================
unit UserScript;

var
  sl: TStringList;

procedure Log(s: string);
begin
  sl.Add(s);
  AddMessage(s);
end;

procedure DumpElem(e: IInterface; indent: string);
var
  i: integer;
  v: string;
begin
  v := '';
  try
    if ElementCount(e) = 0 then v := ' = ' + GetEditValue(e);
  except
    v := ' = <err>';
  end;
  if Assigned(e) then begin
    sl.Add(indent + '[' + Signature(e) + '] ' + Name(e) + v);
    for i := 0 to ElementCount(e) - 1 do
      DumpElem(ElementByIndex(e, i), indent + '    ');
  end else
    sl.Add(indent + '<nil>');
end;

function FileByName(name: string): IInterface;
var
  i: integer;
begin
  Result := nil;
  for i := 0 to FileCount - 1 do
    if GetFileName(FileByIndex(i)) = name then begin
      Result := FileByIndex(i);
      Break;
    end;
end;

function Initialize: integer;
var
  f, skyrim, grp, rec, vanilla: IInterface;
begin
  sl := TStringList.Create;

  f := FileByName('EldenRingCombat.esp');
  if Assigned(f) then begin
    grp := GroupBySignature(f, 'QUST');
    rec := ElementByIndex(grp, 0);
    Log('===== generated: ' + Name(rec) + ' =====');
    DumpElem(ElementBySignature(rec, 'VMAD'), '');
  end else
    Log('generated plugin not loaded');

  skyrim := FileByName('Skyrim.esm');
  if Assigned(skyrim) then begin
    vanilla := RecordByFormID(skyrim, $0002E6FF, False);
    if Assigned(vanilla) then begin
      Log('');
      Log('===== vanilla: ' + Name(vanilla) + ' =====');
      DumpElem(ElementBySignature(vanilla, 'VMAD'), '');
    end else
      Log('vanilla reference quest not found');
  end;

  sl.SaveToFile('C:\Users\Billy\EldenRingCombat\build\vmad-diff.txt');
  sl.Free;

  sl := TStringList.Create;
  sl.Add('done');
  sl.SaveToFile('C:\Users\Billy\EldenRingCombat\build\vmad-diff.done');
  sl.Free;

  Result := 1;
end;

end.
