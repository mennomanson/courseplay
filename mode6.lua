local max, min = math.max, math.min;

function courseplay:handle_mode6(vehicle, allowedToDrive, workSpeed, lx , lz, refSpeed,dt )
	local workTool;
	local specialTool = false
	local stoppedForReason = false
	local forceSpeedLimit = refSpeed 
	local fillLevelPct = 0
	--[[
	if vehicle.attachedCutters ~= nil then
		for cutter, implement in pairs(vehicle.attachedCutters) do
			AICombine.addCutterTrigger(vehicle, cutter);
		end;
	end;
	--]]
	local fieldArea = (vehicle.cp.waypointIndex > vehicle.cp.startWork) and (vehicle.cp.waypointIndex < vehicle.cp.stopWork)
	local workArea = (vehicle.cp.waypointIndex > vehicle.cp.startWork) and (vehicle.cp.waypointIndex < vehicle.cp.finishWork)
	local isFinishingWork = false
	local hasFinishedWork = false
	if vehicle.cp.waypointIndex == vehicle.cp.finishWork and vehicle.cp.abortWork == nil and not vehicle.cp.hasFinishedWork then
		local _,y,_ = getWorldTranslation(vehicle.cp.DirectionNode)
		local _,_,z = worldToLocal(vehicle.cp.DirectionNode,vehicle.Waypoints[vehicle.cp.finishWork].cx,y,vehicle.Waypoints[vehicle.cp.finishWork].cz)
		if not vehicle.isReverseDriving then
			z = -z
		end
		local frontMarker = Utils.getNoNil(vehicle.cp.aiFrontMarker,-3)
		if frontMarker + z -2 < 0 then
			workArea = true
			isFinishingWork = true
		elseif vehicle.cp.finishWork ~= vehicle.cp.stopWork then
			courseplay:setWaypointIndex(vehicle, min(vehicle.cp.finishWork + 1,vehicle.cp.numWaypoints));
		end;
	end;
	if vehicle.cp.hasTransferCourse and vehicle.cp.abortWork ~= nil and vehicle.cp.waypointIndex == 1 then
		courseplay:setWaypointIndex(vehicle,vehicle.cp.startWork+1);
	end
	if fieldArea or vehicle.cp.waypointIndex == vehicle.cp.startWork or vehicle.cp.waypointIndex == vehicle.cp.stopWork +1 then
		workSpeed = 1;
	end
	if (vehicle.cp.waypointIndex == vehicle.cp.stopWork or vehicle.cp.previousWaypointIndex == vehicle.cp.stopWork) and vehicle.cp.abortWork == nil and not vehicle.cp.isLoaded and not isFinishingWork and vehicle.cp.wait then
		allowedToDrive = false
		CpManager:setGlobalInfoText(vehicle, 'WORK_END');
		hasFinishedWork = true
	end

	-- Wait until we have fully started up Threshing
	if vehicle.sampleThreshingStart and isSamplePlaying(vehicle.sampleThreshingStart.sample) then
		-- Only allow us to drive if we are moving backwards.
		if not vehicle.cp.isReverseBackToPoint then
			allowedToDrive = false;
		end;
		courseplay:setInfoText(vehicle, string.format("COURSEPLAY_STARTING_UP_TOOL;%s",tostring(vehicle:getName())));
	end;


	local vehicleIsFolding, vehicleIsFolded, vehicleIsUnfolded = courseplay:isFolding(vehicle);
	for i=1, #(vehicle.cp.workTools) do
		workTool = vehicle.cp.workTools[i];

		-- Why is this here????? Very Confusing Ryan
		local tool = vehicle
		if courseplay:isAttachedCombine(workTool) then
			tool = workTool
			workTool.cp.turnStage = vehicle.cp.turnStage
		end
				
		fillLevelPct = workTool.cp.fillLevelPercent
		local fillUnits = tool:getFillUnits()
		
		local ridgeMarker = vehicle.Waypoints[vehicle.cp.waypointIndex].ridgeMarker
		local nextRidgeMarker = vehicle.Waypoints[min(vehicle.cp.waypointIndex+4,vehicle.cp.numWaypoints)].ridgeMarker
		
		
		local isFolding, isFolded, isUnfolded = courseplay:isFolding(workTool);
		local needsLowering = false
		
		if workTool.spec_aiImplement ~= nil then
			needsLowering = workTool.spec_aiImplement.needsLowering
		end
		
		--speedlimits
		forceSpeedLimit = courseplay:getSpeedWithLimiter(workTool, forceSpeedLimit);
		
		-- stop while folding
		if (isFolding or vehicleIsFolding) and vehicle.cp.turnStage == 0 then
			allowedToDrive = false;
			--courseplay:debug(tostring(workTool.name) .. ": isFolding -> allowedToDrive == false", 6);
		end;

		-- implements, no combine or chopper
		if workTool ~= nil and not workTool.cp.hasSpecializationCutter then
			-- balers
			
			if courseplay:isBaler(workTool) then
				if workArea and vehicle.cp.turnStage == 0 then
				--if vehicle.cp.waypointIndex >= vehicle.cp.startWork + 1 and vehicle.cp.waypointIndex < vehicle.cp.stopWork and vehicle.cp.turnStage == 0 then
																									  --  vehicle, workTool, unfold, lower, turnOn, allowedToDrive, cover, unload, ridgeMarker,forceSpeedLimit,workSpeed)
					specialTool, allowedToDrive,forceSpeedLimit,workSpeed,stoppedForReason = courseplay:handleSpecialTools(vehicle, workTool, true,   true,  true,   allowedToDrive, nil,   nil, nil,forceSpeedLimit,workSpeed);
					if not specialTool then
						-- automatic opening for balers
						fillLevelPct = courseplay:round(workTool.cp.fillLevelPercent, 3);
						local capacity = workTool.cp.capacity
						local fillLevel = workTool.cp.fillLevel
						if workTool.spec_baler ~= nil then
							
							--print(string.format("if courseplay:isRoundbaler(workTool)(%s) and fillLevel(%s) > capacity(%s) * 0.9 and fillLevel < capacity and workTool.spec_baler.unloadingState(%s) == Baler.UNLOADING_CLOSED(%s) then",
							--tostring(courseplay:isRoundbaler(workTool)),tostring(fillLevel),tostring(capacity),tostring(workTool.spec_baler.unloadingState),tostring(Baler.UNLOADING_CLOSED)))
							if courseplay:isRoundbaler(workTool) and fillLevel > capacity * 0.9 and fillLevel < capacity and workTool.spec_baler.unloadingState == Baler.UNLOADING_CLOSED then
								if not workTool.spec_turnOnVehicle.isTurnedOn and not stoppedForReason then
									workTool:setIsTurnedOn(true, false);
								end;
								workSpeed = 0.5;
							elseif fillLevel >= capacity and workTool.spec_baler.unloadingState == Baler.UNLOADING_CLOSED then
								allowedToDrive = false;
								if #(workTool.spec_baler.bales) > 0 and workTool.spec_baleWrapper == nil then --Ensures the baler wrapper combo is empty before unloading
									workTool:setIsUnloadingBale(true, false)
								end
							elseif workTool.spec_baler.unloadingState ~= Baler.UNLOADING_CLOSED then
								allowedToDrive = false
								if workTool.spec_baler.unloadingState == Baler.UNLOADING_OPEN then
									workTool:setIsUnloadingBale(false)
								end
							elseif fillLevel >= 0 and not workTool:getIsTurnedOn() and workTool.spec_baler.unloadingState == Baler.UNLOADING_CLOSED then
								workTool:setIsTurnedOn(true, false);
							end
							if workTool.spec_baleWrapper and workTool.spec_baleWrapper.baleWrapperState == BaleWrapper.STATE_WRAPPER_FINSIHED then --Unloads the baler wrapper combo
								workTool:doStateChange(BaleWrapper.CHANGE_WRAPPER_START_DROP_BALE)
							end
						end
						if workTool.setPickupState ~= nil then
							if workTool.spec_pickup ~= nil and not workTool.spec_pickup.isLowered then
								workTool:setPickupState(true, false);
								courseplay:debug(string.format('%s: lower pickup order', nameNum(workTool)), 17);
							end;
						end;
					end
				end

				if (vehicle.cp.previousWaypointIndex == vehicle.cp.stopWork -1 and workTool.turnOnVehicle.isTurnedOn) or stoppedForReason then
					specialTool, allowedToDrive = courseplay:handleSpecialTools(vehicle,workTool,false,false,false,allowedToDrive,nil,nil)
					if not specialTool and workTool.spec_baler.unloadingState == Baler.UNLOADING_CLOSED then
						workTool:setIsTurnedOn(false, false);
						if workTool.setPickupState ~= nil then
							if workTool.spec_pickup ~= nil and workTool.spec_pickup.isLowered then
								workTool:setPickupState(false, false);
								courseplay:debug(string.format('%s: raise pickup order', nameNum(workTool)), 17);
							end;
						end;
					end
				end

			-- baleloader
			elseif courseplay:isBaleLoader(workTool) or courseplay:isSpecialBaleLoader(workTool) then
				local spec = workTool.spec_baleLoader
				if workArea and fillLevelPct ~= 100 then
					specialTool, allowedToDrive = courseplay:handleSpecialTools(vehicle,workTool,true,true,true,allowedToDrive,nil,nil,nil);
					if not specialTool then
						
						--stop if tool is not ready to get bales
						if not spec.isInWorkPosition 
						or spec.rotatePlatformDirection ~= 0
						or spec.emptyState ~= BaleLoader.EMPTY_NONE	then
							allowedToDrive = false;
						end;
						
						--if tool is not i working position, set it
						if (not spec.isInWorkPosition and fillLevelPct ~= 100 and vehicle.cp.abortWork == nil) or vehicle.cp.runOnceStartCourse then
							--if tool is in working position after load savegame, we have to restart it
							if vehicle.cp.runOnceStartCourse then
								vehicle.cp.runOnceStartCourse = false;
								workTool:doStateChange(BaleLoader.CHANGE_MOVE_TO_TRANSPORT);
							end
							--workTool.grabberIsMoving = true
							--workTool.isInWorkPosition = true
							--BaleLoader.moveToWorkPosition(workTool)
							workTool:doStateChange(BaleLoader.CHANGE_MOVE_TO_WORK);
						end
					end;
				end

				if ((fillLevelPct == 100 or vehicle.cp.isLoaded) and vehicle.cp.hasUnloadingRefillingCourse or vehicle.cp.waypointIndex == vehicle.cp.stopWork) and workTool.isInWorkPosition and not workTool:getIsAnimationPlaying('rotatePlatform') and not workTool:getIsAnimationPlaying('emptyRotate') and not workTool:getIsAnimationPlaying(workTool:getBaleGrabberDropBaleAnimName()) then
					specialTool, allowedToDrive = courseplay:handleSpecialTools(vehicle,workTool,false,false,false,allowedToDrive,nil,nil);
					if not specialTool then
						--workTool.grabberIsMoving = true
						--workTool.isInWorkPosition = false
						--BaleLoader.moveToTransportPosition(workTool)
						workTool:doStateChange(BaleLoader.CHANGE_MOVE_TO_TRANSPORT);
					end;
					-- Ensure we set the lastVaildTipDistance incase update tools doesn't work
					if not vehicle.cp.lastValidTipDistance then
						vehicle.cp.lastValidTipDistance = 0
					end
				end

				if fillLevelPct == 100 and not vehicle.cp.hasUnloadingRefillingCourse then
					vehicle.cp.lastValidTipDistance = nil
					if vehicle.cp.automaticUnloadingOnField then
						specialTool, allowedToDrive = courseplay:handleSpecialTools(vehicle,workTool,false,false,false,allowedToDrive,nil,true); 
						if not specialTool then
							vehicle.cp.unloadOrder = true
						end
						CpManager:setGlobalInfoText(vehicle, 'UNLOADING_BALE');
					end
				end;

				-- stop when unloading
				if workTool.activeAnimations and (workTool:getIsAnimationPlaying('rotatePlatform') or workTool:getIsAnimationPlaying('emptyRotate')) then
					allowedToDrive = false;
				end;

				-- automatic unload
				if vehicle.cp.delayFolding and courseplay:timerIsThrough(vehicle, 'foldBaleLoader', false) then
					vehicle.cp.unloadOrder = true
					vehicle.cp.delayFolding = nil
				end
				
				local distanceToUnload = math.huge
				-- We only want to calc the distance to wait point when reverseing. To save on CPU
				if vehicle.cp.waypointIndex > (vehicle.cp.stopWork + 1) and vehicle.Waypoints[vehicle.cp.waypointIndex].rev then
					if not workTool.cp.realUnloadOrFillNode then
						workTool.cp.realUnloadOrFillNode = courseplay:getRealUnloadOrFillNode(workTool);
					end;
					local toolX, _,toolZ = getWorldTranslation(workTool.cp.realUnloadOrFillNode)
					local targetWaypoint = vehicle.Waypoints[vehicle.cp.waitPoints[3]]
					-- Figure out how far are we from the edge of the previous stack depth
					distanceToUnload = courseplay:distance(toolX,toolZ,targetWaypoint.cx,targetWaypoint.cz) + vehicle.cp.lastValidTipDistance
					courseplay.debugVehicle(17,vehicle,'distanceToUnload = %.2f vehicle.cp.lastValidTipDistance = %.2f',distanceToUnload,vehicle.cp.lastValidTipDistance or 0)
				end
				
				-- Once were with in 1 m stop and unload
				if (not workArea and (distanceToUnload < 1  or fillLevelPct == 0)) or vehicle.cp.unloadOrder then
					specialTool, allowedToDrive = courseplay:handleSpecialTools(vehicle,workTool,false,false,false,allowedToDrive,nil,true);
					if not specialTool then
						if fillLevelPct ~= 0 and not vehicle.cp.unloadOrder then
							CpManager:setGlobalInfoText(vehicle, 'UNLOADING_BALE');
							allowedToDrive = false
						end;
						if workTool.spec_baleLoader.emptyState ~= BaleLoader.EMPTY_NONE then
							if workTool.spec_baleLoader.emptyState == BaleLoader.EMPTY_WAIT_TO_DROP then
								-- (2) drop the bales
								-- print(('%s: set state BaleLoader.CHANGE_DROP_BALES'):format(nameNum(workTool)));
								workTool:doStateChange(BaleLoader.CHANGE_DROP_BALES);
								--g_server:broadcastEvent(BaleLoaderStateEvent:new(workTool, BaleLoader.CHANGE_DROP_BALES), true, nil, workTool)
							elseif workTool.spec_baleLoader.emptyState == BaleLoader.EMPTY_WAIT_TO_SINK then
								-- (3) lower (fold) table
								if not courseplay:getCustomTimerExists(vehicle, 'foldBaleLoader') then
									-- print(('%s: foldBaleLoader timer not running -> set timer 2 seconds'):format(nameNum(workTool)));
									courseplay:setCustomTimer(vehicle, 'foldBaleLoader', 2);
									vehicle.cp.delayFolding = true;
								elseif courseplay:timerIsThrough(vehicle, 'foldBaleLoader', false) then
									-- print(('%s: timer through -> set state BaleLoader.CHANGE_SINK -> reset timer'):format(nameNum(workTool)));
									workTool:doStateChange(BaleLoader.CHANGE_SINK);
									--g_server:broadcastEvent(BaleLoaderStateEvent:new(workTool, BaleLoader.CHANGE_SINK), true, nil, workTool);
									courseplay:resetCustomTimer(vehicle, 'foldBaleLoader', true);
								end;

								-- Change the direction to forward if we were reversing.
								if vehicle.Waypoints[vehicle.cp.waypointIndex].rev then
									-- Add the distance of 1 row of bales. TODO Adjust hud to make this a number of bales and check to see differnce between round and square
									if not vehicle.cp.automaticUnloadingOnField and vehicle.cp.hasUnloadingRefillingCourse then
										-- This is so if the bales are droped in a sell trigger there is no need to adjust where the drop point is case the bales will dissaper
										local triggers = g_currentMission.trailerTipTriggers[workTool]
										if triggers ~= nil and triggers[1].acceptedFillTypes ~= nil and triggers[1].acceptedFillTypes[workTool.cp.fillType] then
											--Do nothing
										else
											-- Get the stack depth when droped set in special tools. The add it to the current stack depth
											local baleRowWidth = workTool.cp.baleRowWidth or 5
											vehicle.cp.lastValidTipDistance = vehicle.cp.lastValidTipDistance - baleRowWidth
										end
									end
									print(('%s: set waypointIndex to next forward point'):format(nameNum(workTool)));
									courseplay:setWaypointIndex(vehicle, courseplay:getNextFwdPoint(vehicle));
									vehicle.cp.ppc:initialize()
								end;
							elseif workTool.emptyState == BaleLoader.EMPTY_WAIT_TO_REDO then
								-- print(('%s: set state BaleLoader.CHANGE_EMPTY_REDO'):format(nameNum(workTool)));
								workTool:doStateChange(BaleLoader.CHANGE_EMPTY_REDO);
								--g_server:broadcastEvent(BaleLoaderStateEvent:new(workTool, BaleLoader.CHANGE_EMPTY_REDO), true, nil, workTool);
							end;
						else
							-- (1) lift (unfold) table
							if BaleLoader.getAllowsStartUnloading(workTool) then
								-- print(('%s: set state BaleLoader.CHANGE_EMPTY_START'):format(nameNum(workTool)));
								workTool:doStateChange(BaleLoader.CHANGE_EMPTY_START);
								--g_server:broadcastEvent(BaleLoaderStateEvent:new(workTool, BaleLoader.CHANGE_EMPTY_START), true, nil, workTool);
							end;
							vehicle.cp.unloadOrder = false;
						end;
					end;
				end;
			--END baleloader


			-- other worktools, tippers, e.g. forage wagon
			else
				if workArea and fillLevelPct ~= 100 and ((vehicle.cp.abortWork == nil) or (vehicle.cp.abortWork ~= nil and vehicle.cp.previousWaypointIndex == vehicle.cp.abortWork) or (vehicle.cp.runOnceStartCourse)) and vehicle.cp.turnStage == 0 then -- and not courseplay:onAlignmentCourse( vehicle ) then
					--courseplay:handleSpecialTools(vehicle,workTool,unfold,lower,turnOn,allowedToDrive,cover,unload)
					specialTool, allowedToDrive = courseplay:handleSpecialTools(vehicle,workTool,true,true,true,allowedToDrive,nil,nil)
					if allowedToDrive then
						if not specialTool then
							--print("282 startOrder")
							courseplay:lowerImplements(vehicle)
							vehicle:raiseAIEvent("onAIStart", "onAIImplementStart")
							vehicle.cp.runOnceStartCourse = false;
							
							--vehicle:raiseAIEvent("onAIEndTurn", "onAIImplementEndTurn", left)
														--unfold
							local recordnumber = min(vehicle.cp.waypointIndex + 2, vehicle.cp.numWaypoints);
							local forecast = Utils.getNoNil(vehicle.Waypoints[recordnumber].ridgeMarker,0)
							local marker = Utils.getNoNil(vehicle.Waypoints[vehicle.cp.waypointIndex].ridgeMarker,0)
							local waypoint = max(marker,forecast)
							if courseplay:isFoldable(workTool) and not isFolding and not isUnfolded then
								if not workTool.cp.hasSpecializationPlow then
									courseplay:debug(string.format('%s: unfold order (foldDir=%d)', nameNum(workTool), workTool.cp.realUnfoldDirection), 17);
									workTool:setFoldDirection(workTool.cp.realUnfoldDirection);
									vehicle.cp.runOnceStartCourse = false;
								elseif waypoint == 2 and vehicle.cp.runOnceStartCourse then --find waypoints and set directions...
									courseplay:debug(string.format('%s: unfold order (foldDir=%d)', nameNum(workTool), workTool.cp.realUnfoldDirection), 17);
									workTool:setFoldDirection(workTool.cp.realUnfoldDirection);
									if workTool:getIsPlowRotationAllowed() then
										AIVehicle.aiRotateLeft(vehicle);
										vehicle.cp.runOnceStartCourse = false;
									end
								elseif vehicle.cp.runOnceStartCourse then
									courseplay:debug(string.format('%s: unfold order (foldDir=%d)', nameNum(workTool), workTool.cp.realUnfoldDirection), 17);
									workTool:setFoldDirection(workTool.cp.realUnfoldDirection);
									vehicle.cp.runOnceStartCourse = false;
								end
							end;
							if not isFolding and isUnfolded then
								courseplay:lowerImplements(vehicle)
							end;
						end;
					end
				elseif not workArea or vehicle.cp.abortWork ~= nil or vehicle.cp.isLoaded or vehicle.cp.previousWaypointIndex == vehicle.cp.stopWork then
					specialTool, allowedToDrive = courseplay:handleSpecialTools(vehicle,workTool,false,false,false,allowedToDrive,nil,nil)
					if not specialTool then
						courseplay:raiseImplements(vehicle)
						
						vehicle:raiseAIEvent("onAIEnd", "onAIImplementEnd")
						
						
						--[[ if not isFolding then
							courseplay:manageImplements(vehicle, false, false, false)
						end;]]

						 --fold
						if courseplay:isFoldable(workTool) and not isFolding and not isFolded then
							if workTool:getIsFoldAllowed() then
								courseplay:debug(string.format('%s: fold order (foldDir=%d)', nameNum(workTool), -workTool.cp.realUnfoldDirection), 17);
								workTool:setFoldDirection(-workTool.cp.realUnfoldDirection);
							elseif workTool.getIsPlowRotationAllowed ~= nil and workTool:getIsPlowRotationAllowed() and workTool.rotationMax == workTool.rotateLeftToMax then
								workTool:setRotationMax(not workTool.rotateLeftToMax);
								courseplay:debug(string.format('%s: rotate plow before folding', nameNum(workTool)), 17);
							end;
						end; 
					end;
				end;
				
				-- done tipping
				if vehicle.cp.totalFillLevel ~= nil and vehicle.cp.totalCapacity ~= nil then
					if vehicle.cp.currentTipTrigger and vehicle.cp.totalFillLevel == 0 then
						courseplay:resetTipTrigger(vehicle, true);
					end

					-- damn, i missed the trigger!
					if vehicle.cp.currentTipTrigger ~= nil then
						local trigger = vehicle.cp.currentTipTrigger
						local triggerId = trigger.triggerId
						if trigger.isPlaceableHeapTrigger then
							triggerId = trigger.rootNode;
						end;

						if trigger.specialTriggerId ~= nil then
							triggerId = trigger.specialTriggerId
						end
						local trigger_x, trigger_y, trigger_z = getWorldTranslation(triggerId);
						local ctx, cty, ctz = getWorldTranslation(vehicle.cp.DirectionNode);

						-- Start reversion value is to check if we have started to reverse
						-- This is used in case we already registered a tipTrigger but changed the direction and might not be in that tipTrigger when unloading. (Bug Fix)
						local startReversing = vehicle.Waypoints[vehicle.cp.waypointIndex].rev and not vehicle.Waypoints[vehicle.cp.previousWaypointIndex].rev;
						if startReversing then
							courseplay:debug(string.format("%s: Is starting to reverse. Tip trigger is reset.", nameNum(vehicle)), 13);
						end;

						local distToTrigger = courseplay:distance(ctx, ctz, trigger_x, trigger_z);
						local isBGA = trigger.bunkerSilo ~= nil 
						local triggerLength = Utils.getNoNil(vehicle.cp.currentTipTrigger.cpActualLength,20)
						local maxDist = isBGA and (vehicle.cp.totalLength + 55) or (vehicle.cp.totalLength + triggerLength); 
						if distToTrigger > maxDist or startReversing then --it's a backup, so we don't need to care about +/-10m
							courseplay:resetTipTrigger(vehicle);
							courseplay:debug(string.format("%s: distance to currentTipTrigger = %d (> %d or start reversing) --> currentTipTrigger = nil", nameNum(vehicle), distToTrigger, maxDist), 1);
						end
					end

					-- tipper is not empty and tractor reaches TipTrigger
					if vehicle.cp.totalFillLevel > 0 and vehicle.cp.currentTipTrigger ~= nil and vehicle.cp.waypointIndex > 3 then
						allowedToDrive,takeOverSteering = courseplay:unload_tippers(vehicle, allowedToDrive,dt);
						courseplay:setInfoText(vehicle, "COURSEPLAY_TIPTRIGGER_REACHED");
					end
					
					
				end;
			end; --END other tools


			-- save last point
			if (fillLevelPct == 100 or vehicle.cp.isLoaded) and workArea and not courseplay:isBaler(workTool) then
				if vehicle.cp.hasUnloadingRefillingCourse and vehicle.cp.abortWork == nil then
					courseplay:setAbortWorkWaypoint(vehicle);
				elseif not vehicle.cp.hasUnloadingRefillingCourse and not vehicle.cp.automaticUnloadingOnField then
					allowedToDrive = false;
					CpManager:setGlobalInfoText(vehicle, 'NEEDS_UNLOADING');
				elseif not vehicle.cp.hasUnloadingRefillingCourse and vehicle.cp.automaticUnloadingOnField then
					allowedToDrive = false;
				end;
			end;

		--COMBINES
		elseif workTool.cp.hasSpecializationCutter then
			--print('I AM A COMBINE or CHOPPER')
			--Start combine
			local isTurnedOn = tool:getIsTurnedOn();
			local pipeState = 0;
			if tool.spec_pipe ~= nil then
				pipeState = courseplay:getTrailerInPipeRangeState(tool)
			end
			if workArea and not tool.aiIsStarted and vehicle.cp.abortWork == nil and vehicle.cp.turnStage == 0 then
											--courseplay:handleSpecialTools(self,workTool,unfold,lower,turnOn,allowedToDrive,cover,unload,ridgeMarker,forceSpeedLimit)
				specialTool, allowedToDrive = courseplay:handleSpecialTools(vehicle,workTool,true,true,true,allowedToDrive,nil,nil,ridgeMarker)
				if not specialTool then
					local weatherStop = not tool:getIsThreshingAllowed(true)

					-- Choppers
					if tool.cp.capacity == 0 then
						if not workTool:getIsUnfolded() then
							--print("unfold and start order")
							vehicle:raiseAIEvent("onAIStart", "onAIImplementStart")
							courseplay:setFoldedStates(workTool)
						elseif not workTool:getIsTurnedOn() then
							--print("restart order")
							courseplay:lowerImplements(vehicle)
						end
						
						--vehicle:raiseAIEvent("onAIStart", "onAIImplementStart")
						--courseplay:lowerImplements(vehicle, true)
						--[[ if courseplay:isFoldable(workTool) and not isTurnedOn and not isFolding and not isUnfolded then
							courseplay:debug(string.format('%s: unfold order (foldDir=%d)', nameNum(workTool), workTool.cp.realUnfoldDirection), 17);
							workTool:setFoldDirection(workTool.cp.realUnfoldDirection);
						end; ]]
						
						if not isFolding and isUnfolded and not isTurnedOn and not vehicle.cp.saveFuel  then
							--[[ courseplay:debug(string.format('%s: Start Treshing', nameNum(tool)), 12);
							tool:setIsTurnedOn(true); ]]
							
							if pipeState > 0 then
								tool:setPipeState(pipeState);
							else
								tool:setPipeState(2);
							end;
						end

						-- stop when there's no trailer to fill
						local chopperWaitForTrailer = false;
						if tool.cp.isChopper and tool.spec_combine.lastValidInputFruitType ~= FruitType.UNKNOWN and fillUnits[tool.spec_combine.fillUnitIndex].fillLevel > 0 then
							if tool.spec_pipe.numObjectsInTriggers == 0 then
								--print("set chopperWaitForTrailer true ")
								chopperWaitForTrailer = true;
							end								
						end;

						if (tool.spec_pipe.numObjectsInTriggers == 0 and vehicle.cp.turnStage == 0) or chopperWaitForTrailer then
							tool.cp.waitingForTrailerToUnload = true;
							--print("set waitingForTrailerToUnload true")
						end;

						
						
						
					-- Combines
					else
						local tankFillLevelPct = tool.cp.fillLevelPercent;
						if not vehicle.cp.isReverseBackToPoint then
							vehicle:raiseAIEvent("onAIStart", "onAIImplementStart")
							courseplay:lowerImplements(vehicle)
							-- WorkTool Unfolding.
							--[[ if courseplay:isFoldable(workTool) and not isTurnedOn and not isFolding and not isUnfolded then
								courseplay:debug(string.format('%s: unfold order (foldDir=%d)', nameNum(workTool), workTool.cp.realUnfoldDirection), 17);
								workTool:setFoldDirection(workTool.cp.realUnfoldDirection);
							end; ]]

							-- Combine Unfolding
							--[[ if courseplay:isFoldable(tool) then
								if not vehicleIsFolding and not vehicleIsUnfolded then
									courseplay:debug(string.format('%s: unfold order (foldDir=%d)', nameNum(tool), tool.cp.realUnfoldDirection), 17);
									tool:setFoldDirection(tool.cp.realUnfoldDirection);
								end;
							end; ]]

							--[[ if not isFolding and isUnfolded and not vehicleIsFolding and vehicleIsUnfolded and tankFillLevelPct < 100 and not tool.waitingForDischarge and not isTurnedOn and not weatherStop then
								print("tool:setIsTurnedOn(true);")
								tool:setIsTurnedOn(true);
							end ]]
						end
						
						--[[
						if tool.overloading ~= nil and tool.overloading.isActive and (tool.courseplayers == nil or tool.courseplayers[1] == nil) and tool.cp.stopWhenUnloading and tankFillLevelPct >= 1 then
							tool.stopForManualUnloader = true
						end
							
						if vehicle.cp.totalFillLevelPercent >= min(vehicle.cp.driveOnAtFillLevel,99) and vehicle.cp.hasUnloadingRefillingCourse then
							if courseplay:timerIsThrough(vehicle, 'emptyStrawBox', false) or not tool.isStrawEnabled then
								if vehicle.cp.abortWork == nil then
									courseplay:setAbortWorkWaypoint(vehicle);
									courseplay:resetCustomTimer(vehicle, 'emptyStrawBox', true);
								end
							else
								allowedToDrive = false;	
							end
							if tool.isStrawEnabled and courseplay:timerIsThrough(vehicle, 'emptyStrawBox', true) and vehicle.cp.abortWork == nil then
								local strawTimer = tool.strawToggleTime or 3500;
								strawTimer = strawTimer / 1000
								courseplay:setCustomTimer(vehicle, 'emptyStrawBox', strawTimer);
							end
						end						
						]]	
						if tankFillLevelPct >= 100 
						or tool.waitingForDischarge 
						or (tool.cp.stopWhenUnloading and tool.overloading ~= nil and  tool.overloading.isActive and tool.courseplayers and tool.courseplayers[1] ~= nil and tool.courseplayers[1].cp.modeState ~= 9) 
						or tool.stopForManualUnloader then
							tool.waitingForDischarge = true;
							allowedToDrive = false;
							
							if tankFillLevelPct >= 100 then
								vehicle:raiseAIEvent("onAIEnd", "onAIImplementEnd")
								CpManager:setGlobalInfoText(vehicle, 'NEEDS_UNLOADING');
							end
							--vehicle:raiseAIEvent("onAIEnd", "onAIImplementEnd")
							--courseplay:lowerImplements(tool, false)
							
							if (tankFillLevelPct < 80 and not tool.cp.stopWhenUnloading) or (tool.cp.stopWhenUnloading and tool.cp.fillLevel == 0) or (tool.courseplayers and tool.courseplayers[1] == nil) then
								courseplay:setReverseBackDistance(vehicle, 2);
								tool.waitingForDischarge = false;
							end;
							if tool.stopForManualUnloader and (tool.cp.fillLevel == 0 or not tool:getDischargeState()) then
								tool.stopForManualUnloader = false
							end
						end;

						if weatherStop then
							allowedToDrive = false;
							vehicle:raiseAIEvent("onAIEnd", "onAIImplementEnd")
							CpManager:setGlobalInfoText(vehicle, 'WEATHER');
						end

					end

					-- Make sure we are lowered when working the field.
					if allowedToDrive and isTurnedOn and not workTool:getIsLowered() and not vehicle.cp.isReverseBackToPoint then
						courseplay:lowerImplements(vehicle)
					end;
				end
			 --Stop combine
			elseif not workArea or vehicle.cp.previousWaypointIndex == vehicle.cp.stopWork or vehicle.cp.abortWork ~= nil then
				local isEmpty = tool.cp.fillLevel == 0
				if vehicle.cp.abortWork == nil and vehicle.cp.wait and vehicle.cp.previousWaypointIndex == vehicle.cp.stopWork then
					allowedToDrive = false;
				end
				if isEmpty then
					specialTool, allowedToDrive = courseplay:handleSpecialTools(vehicle,workTool,false,false,false,allowedToDrive,nil)
				else
					specialTool, allowedToDrive = courseplay:handleSpecialTools(vehicle,workTool,true,false,false,allowedToDrive,nil)
				end
				if not specialTool then
					--[[ if isTurnedOn then
						tool:setIsTurnedOn(false);
						if tool.aiRaise ~= nil then
							tool:aiRaise()
							tool:setPipeState(1)
						end
					end	 ]]
					if vehicle.cp.waypointIndex == vehicle.cp.stopWork or (vehicle.cp.abortWork ~= nil and tool.cp.capacity == 0 ) then
						if  pipeState == 0 and tool.cp.isCombine then
							tool:setPipeState(1)
						end
						vehicle:raiseAIEvent("onAIEnd", "onAIImplementEnd")
						--courseplay:lowerImplements(vehicle, false)
						
						if courseplay:isFoldable(workTool) and isEmpty and not isFolding and not isFolded then
							courseplay:debug(string.format('%s: fold order (foldDir=%d)', nameNum(workTool), -workTool.cp.realUnfoldDirection), 17);
							workTool:setFoldDirection(-workTool.cp.realUnfoldDirection);
						end;
						if courseplay:isFoldable(tool) and isEmpty and not isFolding and not isFolded then
							courseplay:debug(string.format('%s: fold order (foldDir=%d)', nameNum(tool), -tool.cp.realUnfoldDirection), 17);
							tool:setFoldDirection(-tool.cp.realUnfoldDirection);
						end;
					end
				end
				if tool.cp.isCombine and not tool.cp.wantsCourseplayer and tool.cp.fillLevel > 0.1 and tool.courseplayers and #(tool.courseplayers) == 0 and vehicle.cp.waypointIndex == vehicle.cp.stopWork then
					tool.cp.wantsCourseplayer = true
				end
			end
			if tool.cp.isRopaKeiler2 then  -- quick and dirty fix, no time to waste
				if (tool.cp.fillLevelPercent > 20 and  pipeState == 2) or tool.cp.fillLevelPercent >= 100 then
					tool:setPipeState(2)
					allowedToDrive = false
				elseif (tool.cp.fillLevelPercent == 0 and pipeState == 2) or pipeState == 0  then
					tool:setPipeState(1)
				end
			else
				if tool.cp.isCombine and isTurnedOn and tool.cp.fillLevelPercent >80  or ((pipeState > 0 or courseplay:isAttachedCombine(workTool))and not courseplay:isSpecialChopper(workTool))then
					tool:setPipeState(2)
				elseif  pipeState == 0 and tool.cp.isCombine and tool.cp.fillLevel < tool.cp.capacity and workArea then
					tool:setPipeState(1)
				end
			end
			if tool.cp.waitingForTrailerToUnload then
				local mayIDrive = false;
				
				if tool.cp.isCombine or (courseplay:isAttachedCombine(workTool) and not courseplay:isSpecialChopper(workTool)) then
					if tool.cp.isCheckedIn == nil or (pipeState == 0 and tool.cp.fillLevel == 0) then
						--print("618 reset waitingForTrailerToUnload ")
						tool.cp.waitingForTrailerToUnload = false
					end
				elseif tool.cp.isChopper or courseplay:isSpecialChopper(workTool) then
					-- resume driving
					if tool:getDischargeState() > 0  
					or vehicle.cp.turnStage ~= 0 then
						
						if tool.spec_combine.lastValidInputFruitType ~= FruitType.UNKNOWN then
							--print("627 reset waitingForTrailerToUnload ")
							tool.cp.waitingForTrailerToUnload = false;
						else
							mayIDrive = allowedToDrive;
						end;
					end
					if vehicle.cp.abortWork ~= nil then
						mayIDrive = allowedToDrive;
					end
				end
				allowedToDrive = mayIDrive;
			end

			local dx,_,dz = localDirectionToWorld(vehicle.cp.DirectionNode, 0, 0, 1);
			local length = MathUtil.vector2Length(dx,dz);
			if vehicle.cp.turnStage == 0 then
				vehicle.aiThreshingDirectionX = dx/length;
				vehicle.aiThreshingDirectionZ = dz/length;
			else
				vehicle.aiThreshingDirectionX = -(dx/length);
				vehicle.aiThreshingDirectionZ = -(dz/length);
			end
			if vehicle.cp.convoyActive then
				allowedToDrive, workSpeed = courseplay:manageConvoy(vehicle, allowedToDrive, workSpeed)
			end
			
			
		end
		
		-- Begin work or go to abortWork
		if vehicle.cp.previousWaypointIndex == vehicle.cp.startWork and fillLevelPct ~= 100 then
			if vehicle.cp.abortWork ~= nil then
				if vehicle.cp.abortWork < 5 then
					vehicle.cp.abortWork = 6
				end
				courseplay:setWaypointIndex(vehicle, vehicle.cp.abortWork);
				if vehicle.cp.waypointIndex < 2 then
					courseplay:setWaypointIndex(vehicle, 2);
				end
				if vehicle.Waypoints[vehicle.cp.waypointIndex].turnStart or vehicle.Waypoints[vehicle.cp.waypointIndex+1].turnStart  then
					--- Invert lane offset if abortWork is before previous turn point (symmetric lane change)
					if vehicle.cp.symmetricLaneChange and vehicle.cp.laneOffset ~= 0 and not vehicle.cp.switchLaneOffset then
						courseplay:debug(string.format('%s: abortWork + %d: turnStart=%s -> change lane offset back to abortWorks lane', nameNum(vehicle), i-1, tostring(vehicle.Waypoints[vehicle.cp.waypointIndex].turnStart and true or false)), 12);
						courseplay:changeLaneOffset(vehicle, nil, vehicle.cp.laneOffset * -1);
						vehicle.cp.switchLaneOffset = true;
					end;
					courseplay:setWaypointIndex(vehicle, vehicle.cp.waypointIndex - 2);
				end
				if vehicle.cp.realisticDriving then
					local tx, tz = vehicle.Waypoints[vehicle.cp.waypointIndex-2].cx,vehicle.Waypoints[vehicle.cp.waypointIndex-2].cz
					courseplay.debugVehicle( 9, vehicle, "mode 6 634")
					if vehicle.cp.isNavigatingPathfinding == false and courseplay:calculateAstarPathToCoords( vehicle, nil, tx, tz, vehicle.cp.turnDiameter*2, true) then
						courseplay.debugVehicle( 9, vehicle, "mode 6 636")
						courseplay:setCurrentTargetFromList(vehicle, 1);
						vehicle.cp.isNavigatingPathfinding = true;
					elseif not courseplay:onAlignmentCourse( vehicle ) then
						courseplay:startAlignmentCourse( vehicle, vehicle.Waypoints[vehicle.cp.waypointIndex-2], true)
					end
				end
				vehicle.cp.ppc:initialize()
			end
		end
		-- last point reached restart
		if vehicle.cp.abortWork ~= nil then
			if (vehicle.cp.previousWaypointIndex == vehicle.cp.abortWork ) and fillLevelPct ~= 100 then
				courseplay:setWaypointIndex(vehicle, vehicle.cp.abortWork + 2); -- drive to waypoint after next waypoint
				--vehicle.cp.abortWork = nil
				vehicle.cp.ppc:initialize()
			end
			local offset = 8
			if vehicle.cp.realisticDriving then
				offset = 1
			end
			if vehicle.cp.previousWaypointIndex < vehicle.cp.stopWork and vehicle.cp.previousWaypointIndex > vehicle.cp.abortWork + offset + vehicle.cp.abortWorkExtraMoveBack then
				--print(string.format("vehicle.cp.previousWaypointIndex(%s) < vehicle.cp.stopWork(%s) and vehicle.cp.previousWaypointIndex > vehicle.cp.abortWork(%s) + offset(%s) + vehicle.cp.abortWorkExtraMoveBack(%s)"
				--,tostring(vehicle.cp.previousWaypointIndex),tostring(vehicle.cp.stopWork),tostring(vehicle.cp.abortWork),tostring(offset),tostring(vehicle.cp.abortWorkExtraMoveBack)))
				vehicle.cp.abortWork = nil;
			end
		end
	
		
		
	end; --END for i in vehicle.cp.workTools

	
	if hasFinishedWork then
		isFinishingWork = true
		vehicle.cp.hasFinishedWork = true
	end
	return allowedToDrive, workArea, workSpeed, takeOverSteering ,isFinishingWork,forceSpeedLimit
end

function courseplay:manageConvoy(vehicle, allowedToDrive, workSpeed)
	--get my position in convoy and look for the closest combine
	local ownWaypoint = vehicle.cp.waypointIndex
	local position = 1
	local total = 1
	local distance = 0
	local closestDistance = math.huge
	for _,combine in pairs(CpManager.activeCoursePlayers) do
		if combine ~=vehicle and combine.cp.convoyActive and vehicle.Waypoints[1] == combine.Waypoints[1] then
			total = total+1
			if ownWaypoint < combine.cp.waypointIndex then
				position = position + 1
				distance = (combine.cp.waypointIndex - ownWaypoint)*5
				if distance < closestDistance then
					closestDistance = distance
				end
			end
		end		
	end
	
	--when I'm too close to the combine before me, then stop
	if position > 1 then
		if closestDistance < 100 then
			allowedToDrive = false
		end
	else
		closestDistance = 0
	end
	
	--print(string.format("%s: update convoy pos: %s dist: %s",nameNum(vehicle),tostring(position),tostring(closestDistance))) 
	if vehicle.cp.convoy.distance ~= closestDistance then
		vehicle:setCpVar('convoy.distance',closestDistance)
	end
	if vehicle.cp.convoy.number ~= position then
		vehicle:setCpVar('convoy.number',position)
	end
	if vehicle.cp.convoy.members ~= total then
		vehicle:setCpVar('convoy.members',total)
	end

	return allowedToDrive, workSpeed
end