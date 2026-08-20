using System.Collections;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace UnityPlayVerification.Sample
{
    /// <summary>Demonstrates the source-only scenario contract in Editor PlayMode.</summary>
    public sealed class SampleScenario : IPlayVerificationScenario
    {
        public string ScenarioId => "sample-editor-playmode";

        /// <summary>Verifies PlayMode and records one screenshot without judging its pixels.</summary>
        public IEnumerator Execute(PlayVerificationContext context)
        {
            context.Assert("editor-play-mode-active", Application.isPlaying, "Unity entered Editor PlayMode.");
            yield return context.Capture("sample-frame");
        }
    }

    /// <summary>Exposes the sample scenario to Unity Test Framework discovery.</summary>
    public sealed class SampleScenarioTests
    {
        /// <summary>Runs the sample scenario through the receipt-producing harness.</summary>
        [UnityTest]
        public IEnumerator SampleScenario()
        {
            yield return PlayVerificationScenarioRunner.Run(new SampleScenario());
        }
    }
}
