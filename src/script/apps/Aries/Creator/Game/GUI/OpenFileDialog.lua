--[[
Title: Open File Dialog
Author(s): LiXizhi
Date: 2015/9/20
Desc: Display a dialog with text that let user to enter filename. 
use the lib:
------------------------------------------------------------
NPL.load("(gl)script/apps/Aries/Creator/Game/GUI/OpenFileDialog.lua");
local OpenFileDialog = commonlib.gettable("MyCompany.Aries.Game.GUI.OpenFileDialog");
OpenFileDialog.ShowPage("Please enter text", function(result)
	echo(result);
end, default_text, title, filters)
-------------------------------------------------------
]]
NPL.load("(gl)script/apps/Aries/Creator/Game/Common/Files.lua");
local Files = commonlib.gettable("MyCompany.Aries.Game.Common.Files");
local EntityManager = commonlib.gettable("MyCompany.Aries.Game.EntityManager");
local GameLogic = commonlib.gettable("MyCompany.Aries.Game.GameLogic");

local OpenFileDialog = commonlib.gettable("MyCompany.Aries.Game.GUI.OpenFileDialog");
-- whether in save mode. 
OpenFileDialog.IsSaveMode = false;

local page;
function OpenFileDialog.OnInit()
	page = document:GetPageCtrl();
end

-- @param filterName: "model", "bmax", "audio", "texture"
function OpenFileDialog.GetFilters(filterName)
	if(filterName == "model") then
		return {
			{L"全部文件(*.fbx,*.x,*.bmax)",  "*.fbx;*.x;*.bmax"},
			{L"FBX模型(*.fbx)",  "*.fbx"},
			{L"bmax模型(*.bmax)",  "*.bmax"},
			{L"ParaX模型(*.x)",  "*.x"},
		};
	elseif(filterName == "bmax") then
		return {
			{L"bmax模型(*.bmax)",  "*.bmax"},
		};
	elseif(filterName == "audio") then
		return {
			{L"全部文件(*.mp3,*.ogg,*.wav)",  "*.mp3;*.ogg;*.wav"},
			{L"mp3(*.mp3)",  "*.mp3"},
			{L"ogg(*.ogg)",  "*.ogg"},
			{L"wav(*.wav)",  "*.wav"},
		};
	elseif(filterName == "texture") then
		return {
			{L"全部文件(*.png,*.jpg)",  "*.png;*.jpg"},
			{L"png(*.png)",  "*.png"},
			{L"jpg(*.jpg)",  "*.jpg"},
		};
	end
end

-- @param default_text: default text to be displayed. 
-- @param filters: "model", "bmax", "audio", "texture", nil for any file, or filters table
function OpenFileDialog.ShowPage(text, OnClose, default_text, title, filters, IsSaveMode)
	OpenFileDialog.result = nil;
	OpenFileDialog.text = text;
	OpenFileDialog.title = title;
	if(type(filters) == "string") then
		filters = OpenFileDialog.GetFilters(filters)
	end
	OpenFileDialog.filters = filters;
	
	OpenFileDialog.IsSaveMode = IsSaveMode == true;

	local params = {
			url = "script/apps/Aries/Creator/Game/GUI/OpenFileDialog.html", 
			name = "OpenFileDialog.ShowPage", 
			isShowTitleBar = false,
			DestroyOnClose = true,
			bToggleShowHide=false, 
			style = CommonCtrl.WindowFrame.ContainerStyle,
			allowDrag = true,
			click_through = false, 
			enable_esc_key = true,
			bShow = true,
			isTopLevel = true,
			---app_key = MyCompany.Aries.Creator.Game.Desktop.App.app_key, 
			directPosition = true,
				align = "_ct",
				x = -200,
				y = -150,
				width = 400,
				height = 400,
		};
	System.App.Commands.Call("File.MCMLWindowFrame", params);

	if(default_text) then
		params._page:SetUIValue("text", default_text);
	end
	params._page.OnClose = function()
		if(OnClose) then
			OnClose(OpenFileDialog.result);
		end
	end
end


function OpenFileDialog.OnOK()
	if(page) then
		OpenFileDialog.result = page:GetValue("text");
		page:CloseWindow();
	end
end

function OpenFileDialog.OnOpenFileDialog()
	NPL.load("(gl)script/ide/OpenFileDialog.lua");
	local filename = CommonCtrl.OpenFileDialog.ShowDialog_Win32(OpenFileDialog.filters, 
		OpenFileDialog.title,
		ParaIO.GetCurDirectory(0)..(GameLogic.GetWorldDirectory() or ""), 
		OpenFileDialog.IsSaveMode);
	if(filename and page) then
		local fileItem = Files.ResolveFilePath(filename);
		if(fileItem and fileItem.relativeToWorldPath) then
			local filename = fileItem.relativeToWorldPath;
			page:SetValue("text", filename);
		end
	end
end

function OpenFileDialog.GetText()
	return OpenFileDialog.text or L"请输入:";
end