/**
 * @NApiVersion 2.1
 * @NScriptType Restlet
 * @NModuleScope SameAccount
 * Author: Jon Lamb
 * Date: 08/13/2026
 * Version: 1.0
 * Description: Trigger Map/Reduce scripts and poll their progress over JSON — NetSuite's REST API
 *   has no endpoint that executes scripts, so N/task behind a RESTlet is the only programmatic
 *   path. Primarily called by netsuite-cli via `restlet call`. Contract: POST
 *   { script, deployment?, params? } submits the MR (deployment omitted lets NetSuite pick a free
 *   deployment; params are per-run script-parameter overrides) and returns the task id;
 *   GET ?taskid= returns task.checkStatus with stage detail. Deployment audience is Administrator
 *   only, since this can start any Map/Reduce in the account.
 */
define(["require", "exports", "N/log", "N/task"], function (require, exports, log, task) {
    "use strict";
    class ValidationError extends Error {
    }
    const BODY_KEYS = ['script', 'deployment', 'params'];
    const post = (body) => handle(() => {
        const { script, deployment, params } = parseTriggerRequest(body);
        const mrTask = task.create({
            taskType: task.TaskType.MAP_REDUCE,
            scriptId: script,
            ...(deployment !== undefined ? { deploymentId: deployment } : {}),
            ...(params !== undefined ? { params } : {}),
        });
        const taskId = mrTask.submit();
        log.audit('map/reduce submitted', { taskId, script, deployment, params });
        const status = task.checkStatus({ taskId });
        return {
            taskId,
            script,
            deployment: deployment ?? null,
            status: status.status ?? null,
            stage: status.stage ?? null,
        };
    });
    // NetSuite picks a RESTlet response's serialization from the REQUEST's Content-Type header.
    // Bodyless GET calls (how netsuite-cli issues them) carry none, so returning an object fails at
    // platform serialization. Returning a JSON string sidesteps that — same contract as
    // cp_saved_search_rl; JSON-parsing callers see the identical object.
    const get = (params) => JSON.stringify(handle(() => {
        const taskId = params.taskid?.trim() ?? '';
        if (taskId === '') {
            throw new ValidationError('taskid is required — the task id returned by POST');
        }
        return serializeStatus(taskId);
    }));
    const serializeStatus = (taskId) => {
        const status = checkStatus(taskId);
        // checkStatus doesn't throw for an unknown task id — it returns a status object whose status is
        // null (observed in sb2). Surfacing that as an error keeps a typo'd taskid from reading like a
        // valid task that simply hasn't started.
        if (status.status === null || status.status === undefined) {
            throw new ValidationError(`no task found for taskid ${JSON.stringify(taskId)} — check the id returned by POST`);
        }
        return {
            taskId: status.taskId ?? taskId,
            scriptId: status.scriptId ?? null,
            deploymentId: status.deploymentId ?? null,
            status: status.status ?? null,
            stage: status.stage ?? null,
            percentComplete: detail(status, 'getPercentageCompleted'),
            counts: {
                currentTotalSize: detail(status, 'getCurrentTotalSize'),
                pendingMap: detail(status, 'getPendingMapCount'),
                totalMap: detail(status, 'getTotalMapCount'),
                pendingReduce: detail(status, 'getPendingReduceCount'),
                totalReduce: detail(status, 'getTotalReduceCount'),
                pendingOutput: detail(status, 'getPendingOutputCount'),
                totalOutput: detail(status, 'getTotalOutputCount'),
            },
        };
    };
    const checkStatus = (taskId) => {
        try {
            return task.checkStatus({ taskId });
        }
        catch (err) {
            // A task id checkStatus can't find is a caller mistake (typo, other environment, purged task),
            // not a platform failure — so no log.error, same contract as the other ValidationErrors.
            throw new ValidationError(err.message || String(err));
        }
    };
    // checkStatus returns a plain status object for non-Map/Reduce task ids, and the MR getters can
    // throw for stages that haven't produced the figure yet — either way the field nulls out instead
    // of failing a status call that is otherwise answerable.
    const detail = (status, getter) => {
        const method = status[getter];
        if (typeof method !== 'function')
            return null;
        try {
            return method.call(status) ?? null;
        }
        catch {
            return null;
        }
    };
    const parseTriggerRequest = (body) => {
        if (!body || typeof body !== 'object' || Array.isArray(body)) {
            throw new ValidationError('body must be a JSON object: { script, deployment?, params? }');
        }
        const raw = body;
        for (const key of Object.keys(raw)) {
            if (!BODY_KEYS.includes(key)) {
                throw new ValidationError(`unknown key ${key} — valid keys are ${BODY_KEYS.join(', ')}`);
            }
        }
        return {
            script: requireScriptId(raw.script),
            deployment: optionalTrimmedString(raw.deployment, 'deployment'),
            params: optionalParams(raw.params),
        };
    };
    const requireScriptId = (value) => {
        if (typeof value === 'number' && Number.isInteger(value) && value > 0)
            return value;
        if (typeof value === 'string' && value.trim() !== '')
            return value.trim();
        throw new ValidationError('script is required — a customscript_* script id or numeric internal id');
    };
    const optionalTrimmedString = (value, name) => {
        if (value === undefined || value === null || value === '')
            return undefined;
        if (typeof value !== 'string' || value.trim() === '') {
            throw new ValidationError(`${name} must be a non-empty string, got ${JSON.stringify(value)}`);
        }
        return value.trim();
    };
    const optionalParams = (value) => {
        if (value === undefined || value === null)
            return undefined;
        if (typeof value !== 'object' || Array.isArray(value)) {
            throw new ValidationError('params must be an object mapping script-parameter ids to values');
        }
        return value;
    };
    const handle = (operation) => {
        try {
            return operation();
        }
        catch (err) {
            if (err instanceof ValidationError)
                return { error: err.message };
            log.error('cp_mr_driver_rl error', err);
            return { error: err.message || String(err) };
        }
    };
    return { get, post };
});
