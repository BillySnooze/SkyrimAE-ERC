// ============================================================================
//  ERC_VerifyEsp.pas
//  Independent check of data/EldenRingCombat.esp: xEdit parses the plugin from
//  disk and reports what the game would see. Read-only.
// ============================================================================
unit UserScript;

var
  sl: TStringList;

procedure Log(s: string);
begin
  sl.Add(s);
  AddMessage(s);
end;

function B(b: boolean): string;
begin
  if b then Result := 'yes' else Result := 'no';
end;

function Initialize: integer;
var
  i, j, k: integer;
  f, grp, rec, aliases, alias, alfr, vmad, vmadAliases, entry, scripts,
  script: IInterface;
begin
  sl := TStringList.Create;

  f := nil;
  for i := 0 to FileCount - 1 do
    if GetFileName(FileByIndex(i)) = 'EldenRingCombat.esp' then begin
      f := FileByIndex(i);
      Break;
    end;
  if not Assigned(f) then begin
    Log('FAIL: EldenRingCombat.esp was not loaded');
    sl.SaveToFile('C:\Users\Billy\EldenRingCombat\build\esp-verify.txt');
    Result := 1;
    Exit;
  end;
  Log('file loaded: ' + GetFileName(f) + '  masters=' + IntToStr(MasterCount(f)));

  grp := GroupBySignature(f, 'QUST');
  Log('QUST records: ' + IntToStr(ElementCount(grp)));

  rec := ElementByIndex(grp, 0);
  Log('record: ' + Name(rec));
  Log('  EDID: ' + GetEditValue(ElementBySignature(rec, 'EDID')));
  Log('  FULL: ' + GetEditValue(ElementBySignature(rec, 'FULL')));
  Log('  DNAM flags: ' + GetEditValue(ElementByPath(rec, 'DNAM\Flags')));
  Log('  DNAM priority: ' + GetEditValue(ElementByPath(rec, 'DNAM\Priority')));
  Log('  ANAM: ' + GetEditValue(ElementBySignature(rec, 'ANAM')));

  aliases := ElementByName(rec, 'Aliases');
  Log('  aliases: ' + IntToStr(ElementCount(aliases)));
  for j := 0 to ElementCount(aliases) - 1 do begin
    alias := ElementByIndex(aliases, j);
    Log('   alias ' + IntToStr(j) + ' id=' +
        GetEditValue(ElementBySignature(alias, 'ALST')) +
        ' name=' + GetEditValue(ElementBySignature(alias, 'ALID')));
    alfr := ElementBySignature(alias, 'ALFR');
    if Assigned(alfr) then
      Log('     ALFR = ' + GetEditValue(alfr) +
          ' -> ' + GetEditValue(LinksTo(alfr)))
    else
      Log('     ALFR missing');
  end;

  vmad := ElementBySignature(rec, 'VMAD');
  Log('  VMAD: ' + B(Assigned(vmad)));
  if Assigned(vmad) then begin
    Log('   version=' + GetEditValue(ElementByName(vmad, 'Version')));
    vmadAliases := ElementByName(vmad, 'Aliases');
    Log('   alias blocks: ' + IntToStr(ElementCount(vmadAliases)));
    for j := 0 to ElementCount(vmadAliases) - 1 do begin
      entry := ElementByIndex(vmadAliases, j);
      Log('    block ' + IntToStr(j) + ' quest=' +
          GetEditValue(ElementByPath(entry, 'Object Union\Object v2\FormID')) +
          ' alias=' +
          GetEditValue(ElementByPath(entry, 'Object Union\Object v2\Alias')));
      scripts := ElementByName(entry, 'Alias Scripts');
      for k := 0 to ElementCount(scripts) - 1 do begin
        script := ElementByIndex(scripts, k);
        Log('      script: ' +
            GetEditValue(ElementByName(script, 'ScriptName')));
      end;
    end;
  end;

  sl.SaveToFile('C:\Users\Billy\EldenRingCombat\build\esp-verify.txt');
  sl.Free;

  sl := TStringList.Create;
  sl.Add('done');
  sl.SaveToFile('C:\Users\Billy\EldenRingCombat\build\esp-verify.done');
  sl.Free;

  Result := 1;
end;

end.
