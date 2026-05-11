'use strict';

/**
 * Creates the auto-generated connector update PR.
 * Called from the connector repo workflow via actions/github-script.
 *
 * @param {object} params
 * @param {object} params.github   - Octokit client from actions/github-script
 * @param {object} params.context  - GitHub Actions context
 * @param {object} params.core     - @actions/core
 * @param {function} params.require - Node.js require
 * @param {object} params.inputs   - Values passed from the workflow step
 */
module.exports = async function createPr({ github, context, core, require, inputs }) {
    const fs = require('fs');
    const { execSync } = require('child_process');

    const {
        hasCodeChanges,
        gradleBuildFailed,
        analysisFailed,
        pipelineSucceeded,
        branchName,
        codeOwners,
        newVersion
    } = inputs;

    function formatChange(change) {
        const separators = [' - ', ': ', ' \u2013 '];
        let separator = null;
        let splitIndex = -1;

        for (const sep of separators) {
            const idx = change.indexOf(sep);
            if (idx > -1) {
                separator = sep;
                splitIndex = idx;
                break;
            }
        }

        if (splitIndex > -1) {
            const description = change.substring(0, splitIndex);
            const details = change.substring(splitIndex + separator.length);
            const descHasCode = description.includes("'") || description.includes('"') || description.includes('`');

            if (descHasCode) {
                const descFormatted = description
                    .replace(/'([^']+)'/g, '`$1`')
                    .replace(/"([^"]+)"/g, '`$1`');
                return `${descFormatted} - ${details}`;
            }
            return `${description} - \`${details}\``;
        }

        if (change.includes("'") || change.includes('"')) {
            return change.replace(/'([^']+)'/g, '`$1`').replace(/"([^"]+)"/g, '`$1`');
        }

        return change;
    }

    let prBody = '';
    let prTitle = '';

    if (!hasCodeChanges) {
        prBody  = `## Spec-Only Update\n\n`;
        prBody += `This PR contains only spec/documentation updates — no changes were detected in \`client.bal\` or \`types.bal\`.\n\n`;
        prBody += `> \u2139\ufe0f No version bump or analysis is required.\n\n`;
        prBody += `---\n\nManual Review Required - Please review the spec changes and approve if appropriate.\n`;
        prTitle = `[NONE] Auto-generated connector update - no version change`;
    } else {
        let analysis = null;
        try {
            analysis = JSON.parse(fs.readFileSync('analysis_result.json', 'utf8'));
        } catch (e) {
            core.warning('analysis_result.json not found: ' + e.message);
        }

        const changeType = analysis ? analysis.changeType : 'UNKNOWN';

        prBody = `## Version Change Analysis\n\n`;

        if (analysisFailed) {
            prBody += `> \u26a0\ufe0f WARNING: ANALYSIS FAILED \u2014 version and changelog could not be determined automatically. Manual review required.\n\n`;
        }
        if (gradleBuildFailed) {
            prBody += `> \u26a0\ufe0f WARNING: GRADLE BUILD FAILED \u2014 Manual intervention required\n\n`;
        }
        if (!pipelineSucceeded) {
            prBody += `> \u2139\ufe0f NOTE: Gradle build was skipped \u2014 generation pipeline did not succeed, building against old files would give false results.\n\n`;
        }

        prBody += `**Recommended Version Bump:** \`${changeType}\`\n`;
        prBody += `**New Version:** \`${newVersion || 'unknown'}\`\n`;
        if (analysis) prBody += `**Confidence:** ${analysis.confidence}\n`;

        const buildStatusText = gradleBuildFailed
            ? '\u274c FAILED'
            : (!pipelineSucceeded ? '\u23ed\ufe0f Skipped (generation pipeline failed)' : '\u2705 Success');
        prBody += `**Build Status:** ${buildStatusText}\n`;

        if (codeOwners) {
            prBody += `**Code Owners:** ${codeOwners.split(',').map(o => `@${o}`).join(', ')}\n`;
        }

        if (analysis) {
            prBody += `\n### Summary\n${analysis.summary}\n\n`;

            if (analysis.breakingChanges.length > 0) {
                prBody += `### Breaking Changes\n`;
                analysis.breakingChanges.forEach(c => { prBody += `- ${formatChange(c)}\n`; });
                prBody += '\n';
            }
            if (analysis.newFeatures.length > 0) {
                prBody += `### New Features\n`;
                analysis.newFeatures.forEach(f => { prBody += `- ${formatChange(f)}\n`; });
                prBody += '\n';
            }
            if (analysis.bugFixes.length > 0) {
                prBody += `### Improvements\n`;
                analysis.bugFixes.forEach(f => { prBody += `- ${formatChange(f)}\n`; });
                prBody += '\n';
            }
        }

        const hasChangelogUpdate = (() => {
            try {
                const diff = execSync('git diff --name-only origin/main...HEAD -- CHANGELOG.md', { encoding: 'utf8' }).trim();
                if (diff.split('\n').includes('CHANGELOG.md')) return true;
            } catch (err) {
                core.warning(`Unable to determine CHANGELOG.md branch diff: ${err.message}`);
            }
            try {
                const status = execSync('git status --short -- CHANGELOG.md', { encoding: 'utf8' }).trim();
                return status.length > 0;
            } catch (err) {
                core.warning(`Unable to determine CHANGELOG.md working tree status: ${err.message}`);
                return false;
            }
        })();

        prBody += `---\n\n`;
        if (gradleBuildFailed) {
            prBody += `\u26a0\ufe0f BUILD FAILED - Please fix the Gradle build errors before merging.\n`;
        }
        if (hasChangelogUpdate) {
            prBody += `**CHANGELOG.md** has been automatically updated.\n\n`;
        }
        prBody += `Manual Review Required - Please review the changes and approve if appropriate.\n`;

        const doNotMergePrefix = pipelineSucceeded ? '' : '[DO NOT MERGE] ';
        const analysisPrefix   = analysisFailed    ? '[ANALYSIS FAILED] ' : '';
        const buildStatusPfx   = gradleBuildFailed ? '[BUILD FAILED] ' : '';

        prTitle = `${doNotMergePrefix}${buildStatusPfx}${analysisPrefix}[${changeType}] Auto-generated connector update - v${newVersion}`;
    }

    const pr = await github.rest.pulls.create({
        owner: context.repo.owner,
        repo:  context.repo.repo,
        title: prTitle,
        head:  branchName,
        base:  'main',
        body:  prBody
    });

    console.log(`Created PR #${pr.data.number}: ${pr.data.html_url}`);
    core.setOutput('pr_number', pr.data.number);
    core.setOutput('pr_url',    pr.data.html_url);
    core.setOutput('pr_title',  pr.data.title);

    return pr.data.number;
};
