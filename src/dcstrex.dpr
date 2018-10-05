program dcstrex;

{$APPTYPE CONSOLE}

{$R 'version.res' 'version.rc'}

uses
  Windows,
  SysUtils,
  Classes,
  utils in 'utils.pas';

//const
  // $0c020000 = Shenmue 1
  // $8c010000 = Shenmue 2 [and generic address]
//  DC_VIRTUAL_ADDRESS = $0c34FF00;

type
  PBinaryEntry = ^TBinaryEntry;
  TBinaryEntry = record
    Offset: LongWord; // offset ou est lu l'opcode
    Opcode: LongWord; // opcode est la valeur lue (c'est une adresse pour la RAM de la DC, de la forme 8c01....), convertie en offset de string
    Str: string;      // contient la string lue à l'adresse opcode, si s'est effectivement une string. Vide si l'opcode ne renvoyait pas vers une string
  end;

  TListSortCompare = function(Item1, Item2: Pointer): Integer;

var
DC_VIRTUAL_ADDRESS: LongWord; // const normalement !!! voir si il faut adapter...

  Address: TBinaryEntry;
  EntryPtr: PBinaryEntry;
  Stream: TFileStream;
  Opcode, MaxAddress, Offset: LongWord;
  AddressList: TList;
  i: Integer;
  PrgName: string;
  TextF: TextFile;
  Found: Boolean;

// CompareStrings
function CompareStrings(Item1, Item2: PBinaryEntry): Integer;
begin
(*  if (Item1^.Offset = Item2^.Offset) then
    Result := 0
  else if (Item1^.Offset > Item2^.Offset) then
    Result := 1
  else
    Result := -1;*)
  Result := CompareText(Item1^.Str, Item2^.Str);
end;

// IsValidString
// Caractères permettant de reconnaitre une string valide
function IsValidChar(C: Char): Boolean;
begin
{  Result := C in [#$20..#$7C, #$A5, #$AE, #$BB, #$C2..#$C6, #$CA, #$CD, #$DE,
    #$DF, #$E1, #$E2];}
Result := C = #$A1;
end;

// IsNumeric
function IsNumeric(S: string): Boolean;
begin
  try
    StrToInt(Trim(S));
    Result := True;
  except
    Result := False;
  end;
end;

// RetrieveString
function RetrieveString(Offset: LongWord): string;
var
  C: Char;
  Done: Boolean;
  NbChars: Integer;
  
begin
  Result := '';
  Stream.Seek(Offset, soFromBeginning);
  NbChars := 0;
  repeat
    Stream.Read(C, 1);
    Done := not IsValidChar(C);

    // on double les '"' pour éviter des erreurs de séparateur
    if C = '"' then
      Result := Result + '"';

    if not Done then begin
      Result := Result + C;
      Inc(NbChars);
    end;
  until Done;

  // Test si la chaine en vaut la peine

  // Pas les chaines trop courtes
  if (NbChars < 3) then
    Result := '';

  // Pas de chaine uniquement numériques
  if IsNumeric(Result) then
    Result := '';
end;

// CleanMemory
procedure CleanMemory;
var
  i: Integer;
  
begin
  for i := 0 to AddressList.Count - 1 do begin
    PBinaryEntry(AddressList[i])^.Str := ''; // détruire la string
    Dispose(AddressList[i]);
  end;
  AddressList.Free;
  Stream.Free;
end;

function HexToInt(Hex: string): Integer;
const
  HEXADECIMAL_VALUES  = '0123456789ABCDEF';
var
  i: integer;
begin
  Result := 0;
  case Length(Hex) of
    0: Result := 0;
    1..8: for i:=1 to Length(Hex) do
      Result := 16*Result + Pos(Upcase(Hex[i]), HEXADECIMAL_VALUES)-1;
    else for i:=1 to 8 do
      Result := 16*Result + Pos(Upcase(Hex[i]), HEXADECIMAL_VALUES)-1;
  end;
end;

// WinMain
begin
  PrgName := ExtractFileName(ChangeFileExt(ParamStr(0), ''));
  
  WriteLn(
    'Dreamcast Binary Strings Extractor - v', GetShortStringVersion,
    ' - (C)reated by [big_fury]SiZiOUS', sLineBreak,
    'Based on the original idea and source code by Ayla', sLineBreak,
    'http://sbibuilder.shorturl.com/', sLineBreak
  );
  
  if ParamCount < 2 then begin
    WriteLn(ErrOutput,
      'This tool has been written in order to extract strings for Katana executables', sLineBreak,
      'helping you to translate a Dreamcast game in your language (you know, this is', sLineBreak,
      '"ROM hacking").', sLineBreak, sLineBreak,
      'Usage: ', sLineBreak,
      '       ', PrgName, ' <dc_exec.bin> <output.csv> <addr_base>', sLineBreak,
      '       The output generated will be in CSV format (can be opened in any', sLineBreak,
      '       spreadsheet software).', sLineBreak, sLineBreak,
      'Example: ', sLineBreak,
      '       ', PrgName, ' 1ST_READ.BIN strings.csv', sLineBreak, sLineBreak,
      'Thanks flying to: ', sLineBreak,
      '       Ayla for his idea and source code, Manic, Shendream, FamilyGuy, and', sLineBreak,
      '       everyone following the Shenmue Translation Pack project.', sLineBreak,
      '       Visit us at http://shenmuesubs.sourceforge.net/', sLineBreak, sLineBreak,
      'SiZ!^DCS in 2011, Dreamcast still rulez!'
    );
    Halt(1);
  end;
  
  ReportMemoryLeaksOnShutDown := True;

  DC_VIRTUAL_ADDRESS := strtoint(paramstr(3)); //HexToInt(ParamStr(3));

  AddressList := TList.Create;
  Stream := TFileStream.Create(ParamStr(1), fmOpenRead);
  try

    // Infos...
    WriteLn('File: ', ParamStr(1), sLineBreak,
            'Size: ', Stream.Size, ' Byte(s)'
    );
    
    (*  On analyse le binaire pour récupérer toutes les adresses possibles de la
        forme 8C01.... *)
    WriteLn('Analyzing binary addresses...');
    MaxAddress := (DC_VIRTUAL_ADDRESS + Stream.Size);
    i := 0; // on va répéter l'opération 4 fois pour être sur de bien tout passer
    // en revue avec à chaque fois un décalage de 1
    repeat // i >= 4
      
      WriteLn('  Pass ', i + 1, ' of 4...');
      
      repeat // Stream
        Offset := Stream.Position;
        Stream.Read(Opcode, 4);
        if (Opcode > DC_VIRTUAL_ADDRESS) and (Opcode < MaxAddress) then begin
          EntryPtr := New(PBinaryEntry);
          EntryPtr^.Offset := Offset;
          EntryPtr^.Opcode := Opcode - DC_VIRTUAL_ADDRESS;
          EntryPtr^.Str := '';
          AddressList.Add(EntryPtr); // on stocke l'adresse
        end;
      until Stream.Position >= Stream.Size;

      Inc(i);
      Stream.Seek(i, soFromBeginning);  
    until i >= 4;

    (*  Testons maintenant chaque position du tableau pour savoir si effectivement
        il s'agit d'une vraie chaine. *)
    WriteLn('Resolving string for each address entries...');
    for i := 0 to AddressList.Count - 1 do begin
      Address := PBinaryEntry(AddressList[i])^;
      PBinaryEntry(AddressList[i])^.Str := RetrieveString(Address.Opcode);
    end;

    // Trier la liste selon les offsets lus depuis le fichier
    WriteLn('Sorting list by strings...');
    AddressList.Sort(@CompareStrings);

    // On affiche les résultats
    Found := False;
    AssignFile(TextF, ParamStr(2));
    ReWrite(TextF);
    WriteLn('Writing results to "', ParamStr(2), '"...');
    WriteLn(TextF, 'String;String reference offset;Pointer offset value;Decimal pointer offset');
    for i := 0 to AddressList.Count - 1 do begin
      Address := PBinaryEntry(AddressList[i])^;
      if Address.Str <> '' then // si la chaine est vide, l'adresse 8c01... pointait pas vers une string
      begin
        WriteLn(TextF,
          '"', Address.Str, '";',
          '0x', IntToHex(Address.Opcode, 2), ';',
          '0x', IntToHex(Address.Offset, 2), ';',
          Address.Offset
        );
        Found := True;
      end;
    end;
    CloseFile(TextF);

    // Clean empty file
    if Found then
      WriteLn('Done !')
    else begin
      DeleteFile(ParamStr(2));
      WriteLn('Nothing found!');
    end;

  finally
    CleanMemory;
  end;
end.
