#AutoIt3Wrapper_Change2CUI=y

#include <FileConstants.au3>
#include <StringConstants.au3>
#include <Array.au3>
#include <File.au3>

Global $SourceFolder = $CmdLine[1] ;"./Results"
Global $OutputFolder = $CmdLine[2] ;@ScriptDir&"/source/index.html.md"

Global $Log = FileOpen(@ScriptDir & "\SlateGenerator2.log", 2)
Global $DataFile = FileOpen(@ScriptDir & "\TreeHierarchy.csv", 2)

#include "Parser.au3"
#include "DataStorer.au3"
#include "Writer.au3"

Func ExitCleanly()
	FileWrite($Log, "SlateGenerator2 exited cleanly")
	FileClose($Log)
	FileClose($DataFile)
EndFunc



Func IdentifyBlock($Block, $Declaration)
	Local $Kind
	Local $KindFunction

	$Kind = ParseForOneTag($Block, "@module")
	If $Kind Then
		Return "module"
	EndIf

	$Kind = ParseForOneTag($Block, "@type")
	If $Kind Then
		Return "type"
	EndIf


	$KindFunction = ParseFunctionName($Block, $Declaration)
	If $KindFunction[0] Then
		Return "function"
	EndIf

	Return ""
EndFunc





; Main

Local $SourceList = _FileListToArrayRec($SourceFolder, "*", $FLTAR_FILES, $FLTAR_RECUR, $FLTAR_NOSORT, $FLTAR_FULLPATH)
Local $CurrentFile
Local $CarretPos = 0
Local $CommentBlock
Local $CommentKind
Local $CommentInfo[2]

Local $CurrentModule


ConsoleWrite("1. Parsing Source Files... ")
FileWrite($Log, @CRLF&@CRLF&@TAB&"INFO : Building Hierarchy" & @CRLF)
For $i=1 To $SourceList[0]
	$CurrentFile = FileOpen($SourceList[$i], $FO_READ)
	FileWrite($Log, @CRLF&"INFO : Reading File "&$SourceList[$i] & @CRLF)
	While True
		$CommentBlock = ReadNextBlock($CurrentFile, $CarretPos)
		If Not $CommentBlock[1] Then
			ExitLoop
		EndIf

		$CarretPos = $CommentBlock[0]
		$CommentKind = IdentifyBlock($CommentBlock[1], $CommentBlock[2])
		Switch $CommentKind
			Case "function"
				$CommentInfo = ParseFunctionName($CommentBlock[1], $CommentBlock[2])
				AddNode("function", $CurrentModule, $CommentInfo[0], $CommentInfo[1], $SourceList[$i], $CommentBlock[3])
				FileWrite($Log, "INFO : Added function "&$CommentInfo[0]&" to hierarchy" & @CRLF)
			Case "type"
				$CommentInfo[0] = ParseForOneTag($CommentBlock[1], "@type")
				$CommentInfo[1] = ParseForOneTag($CommentBlock[1], "@extends")
				$CommentInfo[1] = StringRegExpReplace($CommentInfo[1], "(.*#)", "")
				AddNode("type", $CurrentModule, $CommentInfo[0], $CommentInfo[1], $SourceList[$i], $CommentBlock[3])
				FileWrite($Log, "INFO : Added type "&$CommentInfo[0]&" to hierarchy" & @CRLF)
			Case "module"
				$CurrentModule = ParseForOneTag($CommentBlock[1], "@module")
				AddNode("module", "", $CurrentModule, "", $SourceList[$i], $CommentBlock[3])
				FileWrite($Log, "INFO : Added type "&$CurrentModule&" to hierarchy" & @CRLF)
		EndSwitch

	WEnd
	$CarretPos = 0
	FileClose($CurrentFile)
Next
ConsoleWrite("Done"&@CRLF)


ConsoleWrite("2. Sorting Hierarchy")
FileWrite($Log, @CRLF&@CRLF&@TAB&"INFO : Sorting Hierarchy" & @CRLF)
DataSort()
ConsoleWrite("Done"&@CRLF)




ConsoleWrite("3. Writing Markdown Documentation... "&@CRLF)
FileWrite($Log, @CRLF&@CRLF&@TAB&"INFO : Writing Markdown Documentation" & @CRLF)

Local $CurrentOutput
Local $CurrentFolder
Local $RegexResult
Local $Line
Local $CarretPos = 0
Local $Results
Local $Output

FileSetPos($DataFile, 0, $FILE_BEGIN)
While True
	FileSetPos($DataFile, $CarretPos, $FILE_BEGIN)
	$Line = FileReadLine($DataFile)
	If @error Then ; eof
		ExitLoop
	Endif

	$CarretPos = FileGetPos($DataFile)

	; find the file/position of the next comment block referenced in the line
	$RegexResult = StringRegExp($Line, "\@F=(.+?),", $STR_REGEXPARRAYMATCH)
	$CurrentFile = FileOpen($RegexResult[0], $FO_READ)

	$RegexResult = StringRegExp($Line, "\@C=(.+?),", $STR_REGEXPARRAYMATCH)
	$DataPos = $RegexResult[0]

	; get the comment block itself
	$Results = ReadNextBlock($CurrentFile, $DataPos)
	$Block = $Results[1]

	; choose the right function to write mardown depending on the type of comment block
	$RegexResult = StringRegExp($Line, "\@K=(.+?),", $STR_REGEXPARRAYMATCH)

	If $RegexResult[0] == "module" Then
		; We need the name of the folder containing this particular source file
		$RegexResult = StringRegExp($Line, "\@F=(.+?),", $STR_REGEXPARRAYMATCH)
		$RegexResult = StringRegExp($RegexResult[0], "\\(.*)\\.*\.lua", $STR_REGEXPARRAYMATCH)
		If @error Then
			$CurrentFolder = ""
		Else
			$CurrentFolder = $RegexResult[0]
		Endif

		; Now we can write the markdown for this module
		$CurrentOutput = WriteModule($Block, $CurrentFolder)
	EndIf

	If $RegexResult[0] == "type" Then
		; We need the name of the Module containing the type
		$RegexResult = StringRegExp($Line, "\@M=(.+?),", $STR_REGEXPARRAYMATCH)

		; Now we can write the markdown for this type
		WriteType($Block, $RegexResult[0], $CurrentOutput)
	EndIf

	FileClose($CurrentFile)
Wend
ConsoleWrite("Done"&@CRLF)

ExitCleanly()