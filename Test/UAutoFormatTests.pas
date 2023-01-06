unit UAutoFormatTests;

{$I ..\Source\dws.inc}

interface

uses
   Classes, SysUtils,
   dwsXPlatformTests, dwsXPlatform,
   dwsComp, dwsCompiler, dwsExprs, dwsDataContext,
   dwsTokenizer, dwsErrors, dwsUtils, Variants, dwsSymbols, dwsSuggestions,
   dwsFunctions, dwsCaseNormalizer, dwsScriptSource, dwsSymbolDictionary,
   dwsCompilerContext, dwsUnicode, dwsJSONConnector, dwsUnitSymbols,
   dwsAutoFormat, dwsPascalTokenizer, dwsCodeDOMParser, dwsCodeDOMPascalParser;

type

   TAutoFormatTests = class (TTestCase)
      private
         FCompiler : TDelphiWebScript;
         FTests : TStringList;
         FAutoFormat : TdwsAutoFormat;
         FPascalRules : TdwsCodeDOMPascalParser;
         FTokRules : TTokenizerRules;

         procedure DoInclude(const scriptName: String; var scriptSource: String);

      public
         procedure SetUp; override;
         procedure TearDown; override;

      published
         procedure CodeStillCompiles;
         procedure CodeStillExecutes;

         procedure SimpleNewLines;
         procedure SimpleBeginEndBlocks;
         procedure SimpleRepeat;
         procedure SimpleWhile;
         procedure SimpleIfThenElse;
         procedure SimpleFuncs;
         procedure FuncCalls;
         procedure SimpleStrings;
         procedure SkipComments;
         procedure SimpleClass;
         procedure Conditionals;
         procedure CaseOf;
         procedure ForLoop;
         procedure ArrayAccess;
         procedure BreakupArrayConst;

   end;

// ------------------------------------------------------------------
// ------------------------------------------------------------------
// ------------------------------------------------------------------
implementation
// ------------------------------------------------------------------
// ------------------------------------------------------------------
// ------------------------------------------------------------------

// ------------------
// ------------------ TAutoFormatTests ------------------
// ------------------

// SetUp
//
procedure TAutoFormatTests.SetUp;
const
   cFilter = '*.pas';
var
   basePath : String;
begin
   FTests:=TStringList.Create;

   basePath:=ExtractFilePath(ParamStr(0));

   CollectFiles(basePath+'SimpleScripts'+PathDelim, cFilter, FTests);
   CollectFiles(basePath+'ArrayPass'+PathDelim, cFilter, FTests);
   CollectFiles(basePath+'LambdaPass'+PathDelim, cFilter, FTests);
   CollectFiles(basePath+'InterfacesPass'+PathDelim, cFilter, FTests);
   CollectFiles(basePath+'OperatorOverloadPass'+PathDelim, cFilter, FTests);
   CollectFiles(basePath+'OverloadsPass'+PathDelim, cFilter, FTests);
   CollectFiles(basePath+'HelpersPass'+PathDelim, cFilter, FTests);
   CollectFiles(basePath+'PropertyExpressionsPass'+PathDelim, cFilter, FTests);
   CollectFiles(basePath+'SetOfPass'+PathDelim, cFilter, FTests);
   CollectFiles(basePath+'AssociativePass'+PathDelim, cFilter, FTests);
   CollectFiles(basePath+'GenericsPass'+PathDelim, cFilter, FTests);
   CollectFiles(basePath+'InnerClassesPass'+PathDelim, cFilter, FTests);
   CollectFiles(basePath+'Algorithms'+PathDelim, cFilter, FTests);

   FCompiler:=TDelphiWebScript.Create(nil);
   FCompiler.Config.CompilerOptions:=FCompiler.Config.CompilerOptions+[coSymbolDictionary, coContextMap];
   FCompiler.OnInclude:=DoInclude;

   FPascalRules := TdwsCodeDOMPascalParser.Create;
   FTokRules := TPascalTokenizerStateRules.Create;

   FAutoFormat := TdwsAutoFormat.Create(
      TdwsParser.Create(FTokRules.CreateTokenizer(nil, nil), FPascalRules.CreateRules)
   );
end;

// TearDown
//
procedure TAutoFormatTests.TearDown;
begin
   FAutoFormat.Free;
   FTokRules.Free;
   FPascalRules.Free;
   FCompiler.Free;
   FTests.Free;
end;

// DoInclude
//
procedure TAutoFormatTests.DoInclude(const scriptName: String; var scriptSource: String);
begin
   scriptSource := LoadTextFromFile('SimpleScripts\'+scriptName);
end;

// CodeStillCompiles
//
procedure TAutoFormatTests.CodeStillCompiles;
var
   source : TStringList;
   i : Integer;
   prog : IdwsProgram;
begin
   source:=TStringList.Create;
   try

      for i:=0 to FTests.Count-1 do begin

         source.LoadFromFile(FTests[i]);
         var processed := FAutoFormat.Process(source.Text);
         prog := FCompiler.Compile(
            processed,
            'Test\'+ExtractFileName(FTests[i])
         );

         CheckEquals(
            False, prog.Msgs.HasErrors,
            FTests[i] + #13#10 + prog.Msgs.AsInfo + #13#10 + processed
         );
      end;

   finally
      source.Free;
   end;
end;

// CodeStillExecutes
//
procedure TAutoFormatTests.CodeStillExecutes;

   function AsInfoWithoutPosition(msgs : TdwsMessageList) : String;
   begin
      if msgs.Count = 0 then Exit;
      Result := msgs[0].Text + #10;
      for var i := 1 to msgs.Count-1 do
         Result := #0 + msgs[i].Text;
   end;

   function FilterLocations(const s : String) : String;
   begin
      Result := s;
      repeat
         var p := Pos('[line', Result);
         if p <= 0 then Exit;
         var p2 := Pos(']', Result, p+5);
         if p2 <= 0 then Exit;
         Result := Copy(Result, 1, p) + Copy(Result, p2);
      until False;
   end;

var
   source, expectedResult : TStringList;
   i : Integer;
   prog : IdwsProgram;
   exec : IdwsProgramExecution;
begin
   source:=TStringList.Create;
   expectedResult := TStringList.Create;
   try

      for i:=0 to FTests.Count-1 do begin

         source.LoadFromFile(FTests[i]);

         prog := FCompiler.Compile(
            source.Text,
            'Test\'+ExtractFileName(FTests[i])
         );

         CheckEquals(
            False, prog.Msgs.HasErrors,
            FTests[i] + ' fail pre-processed compilation'#13#10 + prog.Msgs.AsInfo
         );

         exec := prog.Execute;
         var originalOutput := exec.Result.ToString;
         if exec.Msgs.Count > 0 then
            originalOutput := originalOutput+#13#10+'>>> Runtime Error: '+AsInfoWithoutPosition(exec.Msgs);

         var processed := FAutoFormat.Process(source.Text);

         prog := FCompiler.Compile(
            processed,
            'Test\'+ExtractFileName(FTests[i])
         );

         CheckEquals(
            False, prog.Msgs.HasErrors,
            FTests[i] + ' fails post-formatting' + #13#10 + prog.Msgs.AsInfo + #13#10 + processed
         );

         exec := prog.Execute;
         var output := exec.Result.ToString;
         if exec.Msgs.Count>0 then
            output:=output+#13#10+'>>> Runtime Error: '+AsInfoWithoutPosition(exec.Msgs);

         originalOutput := FilterLocations(originalOutput);
         output := FilterLocations(output);

         CheckEquals(originalOutput, output, FTests[i]);

      end;

   finally
      expectedResult.Free;
      source.Free;
   end;
end;

// SimpleNewLines
//
procedure TAutoFormatTests.SimpleNewLines;
begin
   CheckEquals(
      'var i := 1;'#10'i := i + 1;'#10,
      FAutoFormat.Process(#9#9'var'#9'i:=1;i:=i   +   1   ;    '#10)
   );
   CheckEquals(
      'i := a + b;'#10,
      FAutoFormat.Process('i'#9' := '#9' a+'#9#9'b'#9'  ;'#9#9)
   );
   CheckEquals(
      'abc := +2;'#10,
      FAutoFormat.Process(' abc:=+2;')
   );
   CheckEquals(
      'ab := 0.1e+10;'#10'cd := -45e-1;'#10,
      FAutoFormat.Process(' ab:=0.1e+10;cd:=-45e-1;'#10)
   );
end;

// SimpleBeginEndBlocks
//
procedure TAutoFormatTests.SimpleBeginEndBlocks;
begin
   CheckEquals(
      'begin'#10#9'i := 2;'#10'end;'#10,
      FAutoFormat.Process('Begin i:=2;END;')
   );
   CheckEquals(
      'begin'#10#9'var i := 1;'#10#9'begin'#10#9#9'i := 2;'#10#9'end;'#10'end;'#10,
      FAutoFormat.Process('beGin var i := 1;Begin i:=2;END; end;')
   );
   CheckEquals(
      'beginning := 1;'#10'begin'#10#9'ending := 2;'#10'end;'#10,
      FAutoFormat.Process('beginning:=1;begin ending:=2;end;'#10)
   );
end;

// SimpleRepeat
//
procedure TAutoFormatTests.SimpleRepeat;
begin
   CheckEquals(
      'repeat'#10#9'i += 1;'#10'until i >= 10;'#10,
      FAutoFormat.Process('rePeat i+=1; until i>=10;')
   );
end;

// SimpleWhile
//
procedure TAutoFormatTests.SimpleWhile;
begin
   CheckEquals(
      'while i > 0 do'#10#9'i -= 1;'#10'Done()'#10,
      FAutoFormat.Process('While i>0 do i-=1;Done()')
   );
   CheckEquals(
      'while i > 0 do begin'#10#9'i -= 1;'#10'end;'#10'Done()'#10,
      FAutoFormat.Process('While i>0 do begin i-=1;end;Done()')
   );
end;

// SimpleIfThenElse
//
procedure TAutoFormatTests.SimpleIfThenElse;
begin
   CheckEquals(
      'if b then'#10#9'doit()'#10'else dont();'#10'done()'#10,
      FAutoFormat.Process('if b then doit() else dont();done()')
   );
   CheckEquals(
      'if b then begin'#10#9'if not b then begin'#10#9'end else begin'#10#9'end'#10'end'#10,
      FAutoFormat.Process('if b then begin if not b then begin end else begin end end')
   );
   CheckEquals(
      'for a in b do'#10#9'if c then'#10#9#9'd;'#10,
      FAutoFormat.Process('for a in b do if c then d;')
   );
end;

// SimpleFuncs
//
procedure TAutoFormatTests.SimpleFuncs;
begin
   CheckEquals(
      'procedure Hello;'#10'begin'#10#9'i := 1'#10'end;'#10,
      FAutoFormat.Process('procedure Hello;begin i:=1 end;')
   );
   CheckEquals(
      'procedure PrintBool(v : Variant);'#10'begin'#10#9'PrintLn(if v then ''True'' else ''False'');'#10'end;'#10,
      FAutoFormat.Process('procedure PrintBool(v:Variant);begin PrintLn(if v then''True'' else''False'');end;')
   );
end;

// FuncCalls
//
procedure TAutoFormatTests.FuncCalls;
begin
   CheckEquals(
      'procedure Hello;'#10'begin'#10#9'i := 1'#10'end;'#10,
      FAutoFormat.Process('procedure Hello;begin i:=1 end;')
   );
   CheckEquals(
      'if a then'#10#9'b(0)'#10'else c(1)'#10,
      FAutoFormat.Process('if a then b(0)'#10'else c(1)')
   );
end;

// SimpleStrings
//
procedure TAutoFormatTests.SimpleStrings;
begin
   CheckEquals(
      's := '''';'#10'b := "Hello";'#10,
      FAutoFormat.Process('s:='''';b:="Hello";')
   );
   CheckEquals(
      's := #9"abc"#10'#10,
      FAutoFormat.Process('s:=#9"abc"#10')
   );
end;

// SkipComments
//
procedure TAutoFormatTests.SkipComments;
begin
   CheckEquals(
      'i := 1; // begin'#10'i := 2;'#10'// end'#10,
      FAutoFormat.Process('i:=1;// begin'#10'i:=2;'#10'// end')
   );
   CheckEquals(
      '(* /* *)'#10'i := 1; // begin i:=1'#10'i *= 2 /*end*/ 1;'#10,
      FAutoFormat.Process('(* /* *)'#10'i:=1; // begin i:=1'#10'i*=2/*end*/1;'#10)
   );
   CheckEquals(
      'a'#10#10'/* bla'#10'bla */'#10,
      FAutoFormat.Process('a'#10#10'/* bla'#10'bla */')
   )
end;

// SimpleClass
//
procedure TAutoFormatTests.SimpleClass;
begin
   CheckEquals(
      'type'#10#9'TMy = class'#10#9'end;'#10'type'#10#9'TMyClass = class of TMy;'#10,
      FAutoFormat.Process('type TMy=class end;type TMyClass=class of TMy;')
   );
   CheckEquals(
      'type'#10#9'TMy = class'#10#9#9'FField : Integer'#10#9'end;'#10'/*done'#10,
      FAutoFormat.Process('type TMy=class  FField:Integer end;'#10'/*done')
   );
   CheckEquals(
      'type'#10#9'TMy = class'#10#9#9'public'#10#9#9#9'FField : Integer;'#10#9'end;'#10'/*done'#10,
      FAutoFormat.Process('type TMy=class public FField:Integer; end;'#10'/*done')
   );
end;

// Conditionals
//
procedure TAutoFormatTests.Conditionals;
begin
   CheckEquals(
      '{$ifdef A}'#10'b;'#10'{$endif}'#10,
      FAutoFormat.Process('{$ifdef A}'#10'b;'#10'{$endif}'#10)
   );
   CheckEquals(
      '{$ifdef A} b; {$endif}'#10,
      FAutoFormat.Process('{$ifdef A}b;{$endif}'#10)
   );
end;

// CaseOf
//
procedure TAutoFormatTests.CaseOf;
begin
   CheckEquals(
      'case a of'#10#9'-1..+1 : b'#10'end'#10,
      FAutoFormat.Process('case a of -1..+1:b end'#10)
   );
   CheckEquals(
      'case a of'#10#9'1, 2 : b;'#10#9'3 : c;'#10'else'#10#9'd()'#10'end;'#10,
      FAutoFormat.Process('case a of 1,2:b;3:c;else d()end;')
   );
end;

// ForLoop
//
procedure TAutoFormatTests.ForLoop;
begin
   CheckEquals(
      'for i := 1 to 9 do'#10#9'PrintLn(i);'#10,
      FAutoFormat.Process('for i:=1 to 9 do PrintLn(i);'#10)
   );
end;

// ArrayAccess
//
procedure TAutoFormatTests.ArrayAccess;
begin
   CheckEquals(
      'f()[1].b[2]()'#10,
      FAutoFormat.Process('f () [1] . b [2] ()'#10)
   );
end;

// BreakupArrayConst
//
procedure TAutoFormatTests.BreakupArrayConst;
begin
   CheckEquals(
      'const S = ['#10
       + #9'0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7,'#10
       + #9'0xab, 0x76, 0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf,'#10
       + #9'0x9c, 0xa4, 0x72, 0xc0, 0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5,'#10
       + #9'0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15'#10
      + '];'#10,
      FAutoFormat.Process(
          'const S = [0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,'
        + '0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,'
        + '0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15];'
      )
   );
   CheckEquals(
      'const S = ['#10
       + #9'0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,'#10
       + #9'0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,'#10
       + #9'0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15'#10
      + '];'#10,
      FAutoFormat.Process(
          'const S = [0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,'#10
        + '0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,'#10
        + '0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15];'
      )
   );
end;

// ------------------------------------------------------------------
// ------------------------------------------------------------------
// ------------------------------------------------------------------
initialization
// ------------------------------------------------------------------
// ------------------------------------------------------------------
// ------------------------------------------------------------------

   RegisterTest('AutoFormatTests', TAutoFormatTests);

end.
