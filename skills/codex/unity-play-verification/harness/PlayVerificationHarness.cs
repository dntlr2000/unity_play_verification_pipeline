using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace UnityPlayVerification
{
    /// <summary>Defines one project-specific scenario executed only in an isolated project copy.</summary>
    public interface IPlayVerificationScenario
    {
        string ScenarioId { get; }

        /// <summary>Executes project-specific input, interaction, and state assertions.</summary>
        IEnumerator Execute(PlayVerificationContext context);
    }

    [Serializable]
    internal sealed class PlayVerificationAssertionReceipt
    {
        public string id;
        public bool passed;
        public string detail;
    }

    [Serializable]
    internal sealed class PlayVerificationCaptureReceipt
    {
        public string id;
        public string path;
    }

    [Serializable]
    internal sealed class PlayVerificationReceipt
    {
        public string schemaVersion = "1.0.0";
        public string scenarioId;
        public bool completed;
        public string error;
        public List<string> scenes = new List<string>();
        public List<PlayVerificationAssertionReceipt> assertions = new List<PlayVerificationAssertionReceipt>();
        public List<PlayVerificationCaptureReceipt> captures = new List<PlayVerificationCaptureReceipt>();
    }

    /// <summary>Provides deterministic waits, state assertions, Scene loading, and evidence capture.</summary>
    public sealed class PlayVerificationContext
    {
        private readonly string receiptPath;
        private readonly string screenshotRoot;
        private readonly PlayVerificationReceipt receipt;
        private readonly float timeoutSeconds;
        private readonly HashSet<string> scenePaths = new HashSet<string>(StringComparer.Ordinal);
        private readonly HashSet<string> assertionIds = new HashSet<string>(StringComparer.Ordinal);
        private readonly HashSet<string> captureIds = new HashSet<string>(StringComparer.Ordinal);

        /// <summary>Creates a context from verifier-owned command-line artifact paths.</summary>
        internal PlayVerificationContext(string scenarioId)
        {
            receiptPath = ReadRequiredPathArgument("-upvScenarioResultPath");
            screenshotRoot = ReadRequiredPathArgument("-upvScreenshotRoot");
            var expectedScenarioId = ReadRequiredValueArgument("-upvScenarioId");
            if (!float.TryParse(ReadRequiredValueArgument("-upvScenarioTimeoutSeconds"), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out timeoutSeconds) || timeoutSeconds <= 0f)
            {
                throw new InvalidOperationException("Scenario timeout argument must be a positive invariant number.");
            }
            if (!string.Equals(scenarioId, expectedScenarioId, StringComparison.Ordinal))
            {
                throw new InvalidOperationException("The scenario ID does not match the verifier command line.");
            }

            Directory.CreateDirectory(Path.GetDirectoryName(receiptPath));
            Directory.CreateDirectory(screenshotRoot);
            receipt = new PlayVerificationReceipt { scenarioId = scenarioId };
        }

        /// <summary>Loads one project Scene and waits until the asynchronous operation completes.</summary>
        public IEnumerator LoadScene(string scenePath)
        {
            if (string.IsNullOrWhiteSpace(scenePath) || !scenePath.StartsWith("Assets/", StringComparison.Ordinal) || !scenePath.EndsWith(".unity", StringComparison.OrdinalIgnoreCase))
            {
                throw new ArgumentException("Scene path must be a project-relative Assets/*.unity path.", nameof(scenePath));
            }

            var operation = SceneManager.LoadSceneAsync(scenePath, LoadSceneMode.Single);
            if (operation == null)
            {
                throw new InvalidOperationException("Unity did not create a Scene load operation for " + scenePath + ".");
            }
            while (!operation.isDone)
            {
                yield return null;
            }
            if (scenePaths.Add(scenePath))
            {
                receipt.scenes.Add(scenePath);
            }
        }

        /// <summary>Waits a fixed non-negative number of rendered game frames.</summary>
        public IEnumerator WaitFrames(int frameCount)
        {
            if (frameCount < 0)
            {
                throw new ArgumentOutOfRangeException(nameof(frameCount));
            }
            for (var index = 0; index < frameCount; index++)
            {
                yield return null;
            }
        }

        /// <summary>Waits until a condition succeeds or records a failed assertion at timeout.</summary>
        public IEnumerator WaitUntil(Func<bool> condition, float timeoutSeconds, string assertionId, string detail)
        {
            if (condition == null)
            {
                throw new ArgumentNullException(nameof(condition));
            }
            if (timeoutSeconds <= 0f)
            {
                throw new ArgumentOutOfRangeException(nameof(timeoutSeconds));
            }

            var started = Time.realtimeSinceStartup;
            while (!condition())
            {
                if (Time.realtimeSinceStartup - started >= timeoutSeconds)
                {
                    Assert(assertionId, false, detail + " (timed out)");
                }
                yield return null;
            }
            Assert(assertionId, true, detail);
        }

        /// <summary>Records one named state assertion and throws when it fails.</summary>
        public void Assert(string assertionId, bool passed, string detail)
        {
            ValidateIdentifier(assertionId, nameof(assertionId));
            if (!assertionIds.Add(assertionId))
            {
                throw new InvalidOperationException("Duplicate assertion ID: " + assertionId);
            }
            receipt.assertions.Add(new PlayVerificationAssertionReceipt
            {
                id = assertionId,
                passed = passed,
                detail = detail ?? string.Empty
            });
            if (!passed)
            {
                throw new InvalidOperationException("Scenario assertion failed: " + assertionId + ". " + detail);
            }
        }

        /// <summary>Renders one named PNG through a camera without relying on Game View file capture.</summary>
        public IEnumerator Capture(string captureId)
        {
            ValidateIdentifier(captureId, nameof(captureId));
            if (!captureIds.Add(captureId))
            {
                throw new InvalidOperationException("Duplicate capture ID: " + captureId);
            }

            var path = Path.Combine(screenshotRoot, captureId + ".png");
            yield return null;

            Camera camera = Camera.main;
            GameObject temporaryCameraObject = null;
            if (camera == null)
            {
                temporaryCameraObject = new GameObject("UnityPlayVerificationCaptureCamera");
                camera = temporaryCameraObject.AddComponent<Camera>();
                camera.clearFlags = CameraClearFlags.SolidColor;
                camera.backgroundColor = Color.black;
            }

            const int width = 1280;
            const int height = 720;
            var renderTexture = RenderTexture.GetTemporary(width, height, 24, RenderTextureFormat.ARGB32);
            var previousTarget = camera.targetTexture;
            var previousActive = RenderTexture.active;
            Texture2D texture = null;
            try
            {
                camera.targetTexture = renderTexture;
                camera.Render();
                RenderTexture.active = renderTexture;
                texture = new Texture2D(width, height, TextureFormat.RGB24, false);
                texture.ReadPixels(new Rect(0, 0, width, height), 0, 0, false);
                texture.Apply(false, false);
                File.WriteAllBytes(path, texture.EncodeToPNG());
            }
            finally
            {
                camera.targetTexture = previousTarget;
                RenderTexture.active = previousActive;
                if (texture != null)
                {
                    UnityEngine.Object.DestroyImmediate(texture);
                }
                RenderTexture.ReleaseTemporary(renderTexture);
                if (temporaryCameraObject != null)
                {
                    UnityEngine.Object.DestroyImmediate(temporaryCameraObject);
                }
            }
            if (!File.Exists(path) || new FileInfo(path).Length == 0)
            {
                throw new IOException("Screenshot PNG was not written: " + captureId);
            }
            receipt.captures.Add(new PlayVerificationCaptureReceipt { id = captureId, path = path });
        }

        /// <summary>Marks a successfully exhausted scenario before its receipt is written.</summary>
        internal void Complete()
        {
            receipt.completed = true;
        }

        /// <summary>Records an uncaught scenario error without hiding the test failure.</summary>
        internal void RecordError(Exception exception)
        {
            receipt.completed = false;
            receipt.error = exception == null ? "Unknown scenario error." : exception.ToString();
        }

        /// <summary>Writes the current receipt atomically to the verifier-owned external path.</summary>
        internal void WriteReceipt()
        {
            var temporaryPath = receiptPath + ".tmp";
            File.WriteAllText(temporaryPath, JsonUtility.ToJson(receipt, true));
            if (File.Exists(receiptPath))
            {
                File.Delete(receiptPath);
            }
            File.Move(temporaryPath, receiptPath);
        }

        /// <summary>Returns the verifier-owned overall scenario timeout in realtime seconds.</summary>
        internal float TimeoutSeconds
        {
            get { return timeoutSeconds; }
        }

        /// <summary>Finds one required raw custom command-line value supplied by the verifier.</summary>
        private static string ReadRequiredValueArgument(string name)
        {
            var arguments = Environment.GetCommandLineArgs();
            for (var index = 0; index < arguments.Length - 1; index++)
            {
                if (string.Equals(arguments[index], name, StringComparison.Ordinal))
                {
                    var value = arguments[index + 1];
                    if (!string.IsNullOrWhiteSpace(value))
                    {
                        return value;
                    }
                }
            }
            throw new InvalidOperationException("Required verifier argument is missing: " + name);
        }

        /// <summary>Finds and normalizes one required verifier-owned filesystem argument.</summary>
        private static string ReadRequiredPathArgument(string name)
        {
            return Path.GetFullPath(ReadRequiredValueArgument(name));
        }

        /// <summary>Rejects identifiers that could escape or ambiguously name an artifact.</summary>
        private static void ValidateIdentifier(string value, string parameterName)
        {
            if (string.IsNullOrWhiteSpace(value) || value.Length > 128)
            {
                throw new ArgumentException("Identifier must contain 1-128 characters.", parameterName);
            }
            for (var index = 0; index < value.Length; index++)
            {
                var character = value[index];
                var accepted = char.IsLetterOrDigit(character) || character == '.' || character == '_' || character == '-';
                if (!accepted || (index == 0 && !char.IsLetterOrDigit(character)))
                {
                    throw new ArgumentException("Identifier contains an unsupported character.", parameterName);
                }
            }
        }
    }

    /// <summary>Runs one scenario while guaranteeing an external receipt on success or failure.</summary>
    public static class PlayVerificationScenarioRunner
    {
        /// <summary>Executes the scenario coroutine, writes its receipt, and preserves any failure.</summary>
        public static IEnumerator Run(IPlayVerificationScenario scenario)
        {
            if (scenario == null)
            {
                throw new ArgumentNullException(nameof(scenario));
            }

            var context = new PlayVerificationContext(scenario.ScenarioId);
            Exception failure = null;
            IEnumerator routine = null;
            try
            {
                routine = scenario.Execute(context);
            }
            catch (Exception exception)
            {
                failure = exception;
            }
            if (failure == null && routine == null)
            {
                failure = new InvalidOperationException("Scenario returned a null IEnumerator.");
            }
            if (failure == null)
            {
                var routines = new Stack<IEnumerator>();
                routines.Push(routine);
                var started = Time.realtimeSinceStartup;
                while (routines.Count > 0)
                {
                    if (Time.realtimeSinceStartup - started >= context.TimeoutSeconds)
                    {
                        failure = new TimeoutException("Scenario exceeded its manifest timeout of " + context.TimeoutSeconds + " seconds.");
                        break;
                    }
                    bool moved;
                    object current = null;
                    var activeRoutine = routines.Peek();
                    try
                    {
                        moved = activeRoutine.MoveNext();
                        if (moved)
                        {
                            current = activeRoutine.Current;
                        }
                    }
                    catch (Exception exception)
                    {
                        failure = exception;
                        break;
                    }

                    if (!moved)
                    {
                        routines.Pop();
                        var disposable = activeRoutine as IDisposable;
                        disposable?.Dispose();
                        continue;
                    }
                    var nestedRoutine = current as IEnumerator;
                    if (nestedRoutine != null)
                    {
                        routines.Push(nestedRoutine);
                        continue;
                    }
                    yield return current;
                }
            }

            if (failure == null)
            {
                context.Complete();
            }
            else
            {
                context.RecordError(failure);
            }
            context.WriteReceipt();
            if (failure != null)
            {
                throw new InvalidOperationException("Unity Play Verification scenario failed.", failure);
            }
        }
    }
}
